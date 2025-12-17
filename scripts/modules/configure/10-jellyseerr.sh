#!/bin/bash
#
# 10-jellyseerr.sh - Configure Jellyseerr request manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Jellyseerr"
MODULE_STEP=10
MODULE_TOTAL=12

JELLYFIN_URL="http://localhost:8096"

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Jellyseerr"

    local project_root
    project_root=$(get_project_root)
    local settings_file="${project_root}/data/jellyseerr/config/settings.json"
    local db_dir="${project_root}/data/jellyseerr/config/db"

    if [[ ! -f "$settings_file" ]]; then
        report_log "info" "Jellyseerr settings not found - needs initial setup"
        report_log "info" "Complete setup wizard at http://localhost:5055"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        report_log "warning" "jq not installed - skipping Jellyseerr configuration"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    # Check if already initialized
    local initialized
    initialized=$(jq -r '.public.initialized' "$settings_file" 2>/dev/null || echo "false")

    # Pre-configure Jellyseerr if not initialized
    if [[ "$initialized" != "true" ]]; then
        local admin_user="${ADMIN_USERNAME:-admin}"
        local admin_pass="${ADMIN_PASSWORD:-}"
        local admin_email="${ADMIN_EMAIL:-admin@localhost}"

        if [[ -z "$admin_pass" ]]; then
            report_log "info" "No admin password - Jellyseerr requires manual setup"
            report_log "info" "Visit http://localhost:5055 to configure"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            return 0
        fi

        report_log "info" "Pre-configuring Jellyseerr with Jellyfin..."

        # Authenticate with Jellyfin to get user details
        local auth_resp
        auth_resp=$(curl -s -X POST "${JELLYFIN_URL}/Users/AuthenticateByName" \
            -H "Content-Type: application/json" \
            -H "X-Emby-Authorization: MediaBrowser Client=\"Jellyseerr\", Device=\"Setup\", DeviceId=\"jellyseerr-setup\", Version=\"1.0\"" \
            -d "{\"Username\": \"$admin_user\", \"Pw\": \"$admin_pass\"}" 2>/dev/null)

        local jellyfin_token jellyfin_user_id jellyfin_username
        jellyfin_token=$(echo "$auth_resp" | jq -r '.AccessToken // empty')
        jellyfin_user_id=$(echo "$auth_resp" | jq -r '.User.Id // empty')
        jellyfin_username=$(echo "$auth_resp" | jq -r '.User.Name // empty')

        if [[ -z "$jellyfin_token" ]]; then
            report_log "warning" "Could not authenticate with Jellyfin - manual setup required"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            return 0
        fi

        # Get Jellyfin server info
        local server_info server_id server_name
        server_info=$(curl -s "${JELLYFIN_URL}/System/Info" -H "X-Emby-Token: $jellyfin_token")
        server_id=$(echo "$server_info" | jq -r '.Id')
        server_name=$(echo "$server_info" | jq -r '.ServerName')

        # Get Jellyfin libraries (only Movies and TV Shows, with proper type field)
        local libraries
        libraries=$(curl -s "${JELLYFIN_URL}/Library/VirtualFolders" -H "X-Emby-Token: $jellyfin_token" | \
            jq '[.[] | select(.CollectionType == "movies" or .CollectionType == "tvshows") | {
                id: .ItemId,
                name: .Name,
                enabled: true,
                type: (if .CollectionType == "movies" then "movie" else "show" end)
            }]')

        # Stop Jellyseerr to safely edit config
        docker stop jellyseerr > /dev/null 2>&1 || true
        sleep 2

        # Update settings.json with Jellyfin config
        local updated_settings
        updated_settings=$(jq \
            --arg serverName "$server_name" \
            --arg serverId "$server_id" \
            --arg apiKey "$jellyfin_token" \
            --argjson libraries "$libraries" \
            '.main.mediaServerType = 2 |
             .jellyfin.name = $serverName |
             .jellyfin.ip = "jellyfin" |
             .jellyfin.port = 8096 |
             .jellyfin.serverId = $serverId |
             .jellyfin.apiKey = $apiKey |
             .jellyfin.libraries = $libraries |
             .public.initialized = true' "$settings_file")

        # Write updated settings using docker to handle permissions
        echo "$updated_settings" > /tmp/jellyseerr_settings.json
        docker run --rm \
            -v "${project_root}/data/jellyseerr/config:/config" \
            -v /tmp/jellyseerr_settings.json:/tmp/settings.json:ro \
            alpine sh -c "cp /tmp/settings.json /config/settings.json"

        report_log "success" "Jellyfin connection configured"

        # Create admin user in database
        if [[ -d "$db_dir" ]]; then
            docker run --rm \
                -v "${db_dir}:/db" \
                alpine sh -c "
apk add --no-cache sqlite > /dev/null 2>&1
sqlite3 /db/db.sqlite3 \"
INSERT OR REPLACE INTO user (
    id, email, username, permissions, avatar, userType,
    jellyfinUsername, jellyfinUserId, jellyfinAuthToken, jellyfinDeviceId
) VALUES (
    1,
    '${admin_email}',
    '${jellyfin_username}',
    2088958,
    'https://gravatar.com/avatar/placeholder?d=mm&s=200',
    3,
    '${jellyfin_username}',
    '${jellyfin_user_id}',
    '${jellyfin_token}',
    'jellyseerr-setup'
);
\"
" && report_log "success" "Admin user created: $jellyfin_username" || report_log "warning" "Could not create admin user"
        fi

        # Restart Jellyseerr
        docker start jellyseerr > /dev/null 2>&1 || true
        sleep 5
    fi

    # Get Jellyseerr API key
    local api_key
    api_key=$(jq -r '.main.apiKey' "$settings_file" 2>/dev/null || true)

    if [[ -z "$api_key" ]] || [[ "$api_key" == "null" ]]; then
        report_log "warning" "Jellyseerr API key not found"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    report_log "success" "Jellyseerr configured"

    local radarr_key="${RADARR_API_KEY:-$(get_api_key radarr)}"
    local sonarr_key="${SONARR_API_KEY:-$(get_api_key sonarr)}"

    # Check if Radarr is already configured
    local existing_radarr
    existing_radarr=$(curl -s -H "X-Api-Key: $api_key" \
        "http://localhost:5055/api/v1/settings/radarr" 2>/dev/null || echo "[]")

    if [[ "$existing_radarr" == "[]" ]] && [[ -n "$radarr_key" ]]; then
        print_info "Adding Radarr to Jellyseerr..."

        # Get Radarr quality profile ID
        local profile_id
        profile_id=$(curl -s -H "X-Api-Key: $radarr_key" \
            "http://localhost:7878/api/v3/qualityprofile" 2>/dev/null | \
            jq -r '.[] | select(.name == "HD-1080p") | .id' || echo "1")
        profile_id=${profile_id:-1}

        local radarr_body
        radarr_body=$(cat <<EOF
{
    "name": "Radarr",
    "hostname": "radarr",
    "port": 7878,
    "apiKey": "${radarr_key}",
    "useSsl": false,
    "baseUrl": "",
    "activeProfileId": ${profile_id},
    "activeProfileName": "HD-1080p",
    "activeDirectory": "/media/movies",
    "is4k": false,
    "minimumAvailability": "released",
    "tags": [],
    "isDefault": true,
    "syncEnabled": true,
    "preventSearch": false,
    "tagRequests": false
}
EOF
)
        curl -s -X POST -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            "http://localhost:5055/api/v1/settings/radarr" \
            -d "$radarr_body" > /dev/null 2>&1 && \
            report_log "success" "Radarr added to Jellyseerr" || report_log "warning" "Failed to add Radarr"
    else
        print_info "Radarr already configured in Jellyseerr"
    fi

    # Check if Sonarr is already configured
    local existing_sonarr
    existing_sonarr=$(curl -s -H "X-Api-Key: $api_key" \
        "http://localhost:5055/api/v1/settings/sonarr" 2>/dev/null || echo "[]")

    if [[ "$existing_sonarr" == "[]" ]] && [[ -n "$sonarr_key" ]]; then
        print_info "Adding Sonarr to Jellyseerr..."

        # Get Sonarr quality profile ID
        local profile_id
        profile_id=$(curl -s -H "X-Api-Key: $sonarr_key" \
            "http://localhost:8989/api/v3/qualityprofile" 2>/dev/null | \
            jq -r '.[] | select(.name == "WEB-1080p") | .id' || echo "1")
        profile_id=${profile_id:-1}

        local sonarr_body
        sonarr_body=$(cat <<EOF
{
    "name": "Sonarr",
    "hostname": "sonarr",
    "port": 8989,
    "apiKey": "${sonarr_key}",
    "useSsl": false,
    "baseUrl": "",
    "activeProfileId": ${profile_id},
    "activeProfileName": "WEB-1080p",
    "activeDirectory": "/media/tv",
    "activeAnimeProfileId": ${profile_id},
    "activeAnimeProfileName": "WEB-1080p",
    "activeAnimeDirectory": "/media/tv",
    "tags": [],
    "animeTags": [],
    "is4k": false,
    "isDefault": true,
    "enableSeasonFolders": true,
    "syncEnabled": true,
    "preventSearch": false,
    "tagRequests": false
}
EOF
)
        curl -s -X POST -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            "http://localhost:5055/api/v1/settings/sonarr" \
            -d "$sonarr_body" > /dev/null 2>&1 && \
            report_log "success" "Sonarr added to Jellyseerr" || report_log "warning" "Failed to add Sonarr"
    else
        print_info "Sonarr already configured in Jellyseerr"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
