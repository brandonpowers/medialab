#!/bin/bash
#
# 00-jellyfin.sh - Configure Jellyfin media server
# Completes the setup wizard and creates admin user
# Part of the configure phase - runs first since Jellyseerr depends on it
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Jellyfin"
MODULE_STEP=0
MODULE_TOTAL=13

JELLYFIN_URL="${JELLYFIN_URL}"

# ============================================
# HELPER FUNCTIONS
# ============================================

jellyfin_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(
        -s
        -X "$method"
        -H "Content-Type: application/json"
        -H "X-Emby-Authorization: MediaBrowser Client=\"Medialab Setup\", Device=\"Setup Script\", DeviceId=\"medialab-setup\", Version=\"1.0\""
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" "${JELLYFIN_URL}${endpoint}"
}

check_wizard_complete() {
    local response
    response=$(curl -s "${JELLYFIN_URL}/System/Info/Public" 2>/dev/null || echo '{}')

    if echo "$response" | jq -e '.StartupWizardCompleted == true' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"

    # Load environment
    load_env

    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    local server_name="${SERVER_NAME:-medialab}"
    local language="${LANGUAGE:-en}"

    print_section "Configuring Jellyfin"

    # Wait for Jellyfin to be ready (basic API)
    report_log "info" "Waiting for Jellyfin to be ready..."
    local max_wait=60
    local waited=0

    while ! curl -s "${JELLYFIN_URL}/System/Info/Public" > /dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            report_log "warning" "Jellyfin not responding after ${max_wait}s - skipping auto-configuration"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            return 0
        fi
    done

    report_log "success" "Jellyfin is responding"

    # Check if we have password
    if [[ -z "$admin_pass" ]]; then
        report_log "warning" "No admin password configured - Jellyfin requires manual setup"
        report_log "info" "Complete setup at: ${JELLYFIN_URL}"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    # Check if wizard is already complete first (skip waiting for startup API if so)
    if check_wizard_complete; then
        report_log "warning" "Jellyfin wizard already completed - cannot auto-configure"
        report_log "info" "To reconfigure, run: docker compose down && sudo rm -rf data/jellyfin/config/* && docker compose up -d"
        report_log "info" "Then run: ./medialab configure"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    # Wait for Startup API to be fully ready (needs extra time after basic API is up)
    # On fresh installs, Jellyfin takes time to initialize the startup wizard
    report_log "info" "Waiting for Jellyfin startup wizard API..."
    waited=0
    local startup_api_ready=false
    while [[ $waited -lt 60 ]]; do
        # Check if startup API is available
        local startup_response
        startup_response=$(curl -s "${JELLYFIN_URL}/Startup/User" \
            -H "X-Emby-Authorization: MediaBrowser Client=\"Medialab\", Device=\"Setup\", DeviceId=\"setup\", Version=\"1.0\"" 2>/dev/null || echo "")

        if echo "$startup_response" | grep -q "Name"; then
            startup_api_ready=true
            report_log "success" "Startup wizard API is ready"
            break
        fi

        # Check if wizard completed while waiting (race condition)
        if check_wizard_complete; then
            report_log "warning" "Jellyfin wizard completed while waiting - cannot auto-configure"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            return 0
        fi

        sleep 2
        waited=$((waited + 2))
    done

    if [[ "$startup_api_ready" != "true" ]]; then
        report_log "warning" "Jellyfin startup wizard API not available after 60s"
        report_log "info" "Complete setup manually at: ${JELLYFIN_URL}"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    # Language/culture mapping
    local ui_culture="en-US"
    local metadata_country="US"

    case "$language" in
        es) ui_culture="es"; metadata_country="ES" ;;
        fr) ui_culture="fr"; metadata_country="FR" ;;
        de) ui_culture="de"; metadata_country="DE" ;;
        it) ui_culture="it"; metadata_country="IT" ;;
        pt) ui_culture="pt"; metadata_country="PT" ;;
        nl) ui_culture="nl"; metadata_country="NL" ;;
        pl) ui_culture="pl"; metadata_country="PL" ;;
        ru) ui_culture="ru"; metadata_country="RU" ;;
        ja) ui_culture="ja"; metadata_country="JP" ;;
        zh) ui_culture="zh"; metadata_country="CN" ;;
        ko) ui_culture="ko"; metadata_country="KR" ;;
    esac

    # Run startup wizard - must happen BEFORE wizard is completed elsewhere
    report_log "info" "Running Jellyfin setup wizard..."

    # Step 1: Set startup configuration (language, metadata settings)
    local config_payload
    config_payload=$(jq -n \
        --arg uiCulture "$ui_culture" \
        --arg metadataCountry "$metadata_country" \
        '{
            "UICulture": $uiCulture,
            "MetadataCountryCode": $metadataCountry,
            "PreferredMetadataLanguage": $uiCulture
        }')

    if jellyfin_api POST "/Startup/Configuration" "$config_payload" > /dev/null 2>&1; then
        report_log "success" "Set language/metadata configuration"
    else
        report_log "warning" "Could not set configuration"
    fi

    # Step 2: Update the default startup user with our credentials
    # On fresh install, Jellyfin has a default user that we UPDATE (not create)
    report_log "info" "Setting admin user: $admin_user"

    local user_payload
    user_payload=$(jq -n \
        --arg name "$admin_user" \
        --arg password "$admin_pass" \
        '{
            "Name": $name,
            "Password": $password
        }')

    local user_result
    user_result=$(jellyfin_api POST "/Startup/User" "$user_payload" 2>&1)
    local user_status=$?

    if [[ $user_status -eq 0 ]] && [[ ! "$user_result" =~ "Error" ]]; then
        report_log "success" "Admin user configured"
    else
        report_log "error" "Failed to configure admin user - wizard may have been completed elsewhere"
        report_log "info" "Error: $user_result"
    fi

    # Step 3: Complete the setup wizard
    report_log "info" "Completing setup wizard..."

    if jellyfin_api POST "/Startup/Complete" > /dev/null 2>&1; then
        report_log "success" "Setup wizard completed"
    else
        report_log "warning" "Could not complete wizard via API"
    fi

    # Step 4: Set server name via config file (more reliable)
    sleep 2
    docker exec jellyfin sed -i "s|<ServerName>[^<]*</ServerName>|<ServerName>${server_name}</ServerName>|" /config/config/system.xml 2>/dev/null || true
    docker exec jellyfin sed -i "s|<ServerName />|<ServerName>${server_name}</ServerName>|" /config/config/system.xml 2>/dev/null || true

    # Verify completion
    sleep 1
    if check_wizard_complete; then
        report_log "success" "Jellyfin configured successfully"
        report_log "info" "Server name: $server_name"
        report_log "info" "Admin user: $admin_user"
        report_log "info" "Access at: ${JELLYFIN_URL}"

        # Step 5: Configure media libraries
        report_log "info" "Configuring media libraries..."

        # Authenticate to get access token
        local auth_response
        auth_response=$(curl -s -X POST "${JELLYFIN_URL}/Users/AuthenticateByName" \
            -H "Content-Type: application/json" \
            -H "X-Emby-Authorization: MediaBrowser Client=\"Medialab Setup\", Device=\"Setup Script\", DeviceId=\"medialab-setup\", Version=\"1.0\"" \
            -d "{\"Username\": \"$admin_user\", \"Pw\": \"$admin_pass\"}" 2>/dev/null)

        local access_token
        access_token=$(echo "$auth_response" | jq -r '.AccessToken // empty' 2>/dev/null)

        if [[ -n "$access_token" ]]; then
            # Check if libraries already exist
            local existing_libs
            existing_libs=$(curl -s "${JELLYFIN_URL}/Library/VirtualFolders" \
                -H "X-Emby-Token: $access_token" 2>/dev/null | jq -r '.[].Name' 2>/dev/null)

            # Add Movies library
            if ! echo "$existing_libs" | grep -q "^Movies$"; then
                curl -s -X POST "${JELLYFIN_URL}/Library/VirtualFolders?collectionType=movies&refreshLibrary=false&name=Movies" \
                    -H "X-Emby-Token: $access_token" \
                    -H "Content-Type: application/json" \
                    -d '{"LibraryOptions": {"PathInfos": [{"Path": "/media/movies"}], "EnableRealtimeMonitor": true, "PreferredMetadataLanguage": "en", "MetadataCountryCode": "US"}}' > /dev/null 2>&1 && \
                    report_log "success" "Added Movies library" || report_log "warning" "Could not add Movies library"
            fi

            # Add TV Shows library
            if ! echo "$existing_libs" | grep -q "^TV Shows$"; then
                curl -s -X POST "${JELLYFIN_URL}/Library/VirtualFolders?collectionType=tvshows&refreshLibrary=false&name=TV%20Shows" \
                    -H "X-Emby-Token: $access_token" \
                    -H "Content-Type: application/json" \
                    -d '{"LibraryOptions": {"PathInfos": [{"Path": "/media/tv"}], "EnableRealtimeMonitor": true, "PreferredMetadataLanguage": "en", "MetadataCountryCode": "US"}}' > /dev/null 2>&1 && \
                    report_log "success" "Added TV Shows library" || report_log "warning" "Could not add TV Shows library"
            fi

            # Add Music library
            if ! echo "$existing_libs" | grep -q "^Music$"; then
                curl -s -X POST "${JELLYFIN_URL}/Library/VirtualFolders?collectionType=music&refreshLibrary=false&name=Music" \
                    -H "X-Emby-Token: $access_token" \
                    -H "Content-Type: application/json" \
                    -d '{"LibraryOptions": {"PathInfos": [{"Path": "/media/music"}], "EnableRealtimeMonitor": true, "PreferredMetadataLanguage": "en", "MetadataCountryCode": "US"}}' > /dev/null 2>&1 && \
                    report_log "success" "Added Music library" || report_log "warning" "Could not add Music library"
            fi
        else
            report_log "warning" "Could not authenticate - libraries may need manual configuration"
        fi
    else
        report_log "warning" "Wizard may not have completed - check ${JELLYFIN_URL}"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
    return 0
}

main "$@"
