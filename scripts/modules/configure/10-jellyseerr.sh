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

    # Get Jellyseerr API key
    local api_key
    api_key=$(jq -r '.main.apiKey' "$settings_file" 2>/dev/null || true)

    if [[ -z "$api_key" ]] || [[ "$api_key" == "null" ]]; then
        report_log "info" "Jellyseerr not initialized - complete setup wizard first"
        report_log "info" "Visit http://localhost:5055 to configure Jellyseerr"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    report_log "success" "Jellyseerr API key found"

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
