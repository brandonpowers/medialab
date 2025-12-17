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

    # Configure Forms authentication via config file (API is unreliable)
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    local config_file
    config_file="$(get_project_root)/data/bazarr/config/config/config.yaml"

    if [[ -n "$admin_pass" ]] && [[ -f "$config_file" ]]; then
        print_info "Configuring Forms authentication..."

        # Stop Bazarr to safely edit config
        docker stop bazarr > /dev/null 2>&1 || true

        # Bazarr requires MD5 hash of the password
        local pass_hash
        pass_hash=$(echo -n "$admin_pass" | md5sum | cut -d' ' -f1)

        # Update auth section in config file
        sed -i "s/^  type: .*/  type: form/" "$config_file"
        sed -i "s/^  username: .*/  username: $admin_user/" "$config_file"
        sed -i "s/^  password: .*/  password: $pass_hash/" "$config_file"

        # Restart Bazarr
        docker start bazarr > /dev/null 2>&1 || true
        sleep 3

        report_log "success" "Forms authentication configured for user: $admin_user"
    fi

    # Link Sonarr to Bazarr
    if [[ -n "${SONARR_API_KEY:-}" ]]; then
        print_info "Linking Sonarr to Bazarr..."
        local sonarr_body
        sonarr_body=$(cat <<EOF
{
    "sonarr": {
        "ip": "sonarr",
        "port": 8989,
        "base_url": "/",
        "ssl": false,
        "apikey": "${SONARR_API_KEY}",
        "full_update": "Daily",
        "only_monitored": false
    },
    "general": {
        "use_sonarr": true
    }
}
EOF
)
        curl -s -X POST "http://localhost:6767/api/system/settings" \
            -H "x-api-key: $api_key" \
            -H "Content-Type: application/json" \
            -d "$sonarr_body" > /dev/null 2>&1 && \
            report_log "success" "Sonarr linked" || report_log "warning" "Manual Sonarr configuration may be needed"
    fi

    # Link Radarr to Bazarr
    if [[ -n "${RADARR_API_KEY:-}" ]]; then
        print_info "Linking Radarr to Bazarr..."
        local radarr_body
        radarr_body=$(cat <<EOF
{
    "radarr": {
        "ip": "radarr",
        "port": 7878,
        "base_url": "/",
        "ssl": false,
        "apikey": "${RADARR_API_KEY}",
        "full_update": "Daily",
        "only_monitored": false
    },
    "general": {
        "use_radarr": true
    }
}
EOF
)
        curl -s -X POST "http://localhost:6767/api/system/settings" \
            -H "x-api-key: $api_key" \
            -H "Content-Type: application/json" \
            -d "$radarr_body" > /dev/null 2>&1 && \
            report_log "success" "Radarr linked" || report_log "warning" "Manual Radarr configuration may be needed"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
