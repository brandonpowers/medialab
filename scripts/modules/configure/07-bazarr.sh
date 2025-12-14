#!/bin/bash
#
# 07-bazarr.sh - Configure Bazarr subtitle manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Bazarr"
MODULE_STEP=7
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Bazarr"

    sleep 3
    local api_key
    api_key=$(get_api_key "bazarr")

    if [[ -z "$api_key" ]]; then
        report_log "warning" "Bazarr API key not found - it may need manual configuration"
        print_info "Visit http://localhost:6767 to complete Bazarr setup"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    report_log "success" "Bazarr API key: $api_key"

    # Configure authentication
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    if [[ -n "$admin_pass" ]]; then
        print_info "Configuring Bazarr authentication..."
        local auth_body
        auth_body=$(cat <<EOF
{
    "type": "form",
    "username": "${admin_user}",
    "password": "${admin_pass}"
}
EOF
)
        curl -s -X PATCH "http://localhost:6767/api/system/settings/auth" \
            -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d "$auth_body" > /dev/null 2>&1 && \
            report_log "success" "Authentication configured" || report_log "warning" "Could not configure authentication"
    fi

    # Link Sonarr to Bazarr
    if [[ -n "${SONARR_API_KEY:-}" ]]; then
        print_info "Linking Sonarr to Bazarr..."
        local sonarr_body
        sonarr_body=$(cat <<EOF
{
    "ip": "sonarr",
    "port": 8989,
    "base_url": "/",
    "ssl": false,
    "apikey": "${SONARR_API_KEY}",
    "full_update": "Daily",
    "only_monitored": false
}
EOF
)
        curl -s -X PATCH "http://localhost:6767/api/system/settings/sonarr" \
            -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d "$sonarr_body" > /dev/null 2>&1 && \
            report_log "success" "Sonarr linked" || report_log "warning" "Manual Sonarr configuration may be needed"

        # Enable Sonarr in general settings
        curl -s -X PATCH "http://localhost:6767/api/system/settings/general" \
            -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d '{"use_sonarr": true}' > /dev/null 2>&1 || true
    fi

    # Link Radarr to Bazarr
    if [[ -n "${RADARR_API_KEY:-}" ]]; then
        print_info "Linking Radarr to Bazarr..."
        local radarr_body
        radarr_body=$(cat <<EOF
{
    "ip": "radarr",
    "port": 7878,
    "base_url": "/",
    "ssl": false,
    "apikey": "${RADARR_API_KEY}",
    "full_update": "Daily",
    "only_monitored": false
}
EOF
)
        curl -s -X PATCH "http://localhost:6767/api/system/settings/radarr" \
            -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d "$radarr_body" > /dev/null 2>&1 && \
            report_log "success" "Radarr linked" || report_log "warning" "Manual Radarr configuration may be needed"

        # Enable Radarr in general settings
        curl -s -X PATCH "http://localhost:6767/api/system/settings/general" \
            -H "X-Api-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d '{"use_radarr": true}' > /dev/null 2>&1 || true
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
