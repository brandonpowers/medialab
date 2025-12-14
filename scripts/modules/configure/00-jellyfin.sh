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

JELLYFIN_URL="http://localhost:8096"

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
        -H "X-Emby-Authorization: MediaBrowser Client=\"Homelab Setup\", Device=\"Setup Script\", DeviceId=\"homelab-setup\", Version=\"1.0\""
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
    local server_name="${SERVER_NAME:-homelab}"
    local language="${LANGUAGE:-en}"

    print_section "Configuring Jellyfin"

    # Wait for Jellyfin to be ready
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

    # Check if wizard is already complete
    if check_wizard_complete; then
        report_log "info" "Jellyfin setup wizard already completed"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    # Check if we have password
    if [[ -z "$admin_pass" ]]; then
        report_log "warning" "No admin password configured - Jellyfin requires manual setup"
        report_log "info" "Complete setup at: ${JELLYFIN_URL}"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        finish_progress "complete" "$MODULE_NAME"
        return 0
    fi

    report_log "info" "Completing Jellyfin setup wizard..."

    # Step 1: Get initial configuration
    local initial_config
    initial_config=$(jellyfin_api GET "/Startup/Configuration" 2>/dev/null || echo '{}')

    # Step 2: Set startup configuration (language, metadata country)
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

    local config_payload
    config_payload=$(jq -n \
        --arg uiCulture "$ui_culture" \
        --arg metadataCountry "$metadata_country" \
        --arg serverName "$server_name" \
        '{
            "UICulture": $uiCulture,
            "MetadataCountryCode": $metadataCountry,
            "PreferredMetadataLanguage": $uiCulture,
            "ServerName": $serverName
        }')

    if jellyfin_api POST "/Startup/Configuration" "$config_payload" > /dev/null 2>&1; then
        report_log "success" "Set Jellyfin configuration"
    else
        report_log "warning" "Could not set Jellyfin configuration"
    fi

    # Step 3: Create admin user
    report_log "info" "Creating admin user: $admin_user"

    local user_payload
    user_payload=$(jq -n \
        --arg name "$admin_user" \
        --arg password "$admin_pass" \
        '{
            "Name": $name,
            "Password": $password
        }')

    if jellyfin_api POST "/Startup/User" "$user_payload" > /dev/null 2>&1; then
        report_log "success" "Created admin user"
    else
        report_log "warning" "Could not create admin user - may already exist"
    fi

    # Step 4: Complete the wizard
    report_log "info" "Completing setup wizard..."

    if jellyfin_api POST "/Startup/Complete" "" > /dev/null 2>&1; then
        report_log "success" "Setup wizard completed"
    else
        report_log "warning" "Could not complete wizard - may need manual completion"
    fi

    # Verify
    sleep 2
    if check_wizard_complete; then
        report_log "success" "Jellyfin is ready"
        report_log "info" "Access at: ${JELLYFIN_URL}"
    else
        report_log "warning" "Wizard may not have completed - check ${JELLYFIN_URL}"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
