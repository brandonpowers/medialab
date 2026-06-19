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

    local api_key
    api_key=$(wait_for_api_key "bazarr")

    if [[ -z "$api_key" ]]; then
        report_log "warning" "Bazarr API key not found - it may need manual configuration"
        print_info "Visit ${BAZARR_URL} to complete Bazarr setup"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    report_log "success" "Bazarr API key: $api_key"

    # Configure via config file (API is unreliable for settings updates)
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    local config_file
    config_file="$(get_project_root)/data/bazarr/config/config/config.yaml"

    if [[ -f "$config_file" ]]; then
        print_info "Configuring Bazarr via config file..."

        # Stop Bazarr to safely edit config
        docker compose stop bazarr > /dev/null 2>&1 || true

        # Configure Forms authentication
        if [[ -n "$admin_pass" ]]; then
            # Bazarr requires MD5 hash of the password
            local pass_hash
            pass_hash=$(echo -n "$admin_pass" | md5sum | cut -d' ' -f1)

            # Update auth section in config file
            sed -i "s/^  type: .*/  type: form/" "$config_file"
            sed -i "s/^  username: .*/  username: $admin_user/" "$config_file"
            sed -i "s/^  password: .*/  password: $pass_hash/" "$config_file"
            report_log "success" "Forms authentication configured for user: $admin_user"
        fi

        # Enable and configure Sonarr
        if [[ -n "${SONARR_API_KEY:-}" ]]; then
            print_info "Linking Sonarr to Bazarr..."
            sed -i "s/use_sonarr: false/use_sonarr: true/" "$config_file"
            # Update sonarr section
            sed -i "/^sonarr:/,/^[a-z]/ {
                s/apikey: .*/apikey: ${SONARR_API_KEY}/
                s/ip: .*/ip: sonarr/
            }" "$config_file"
            report_log "success" "Sonarr linked"
        fi

        # Enable and configure Radarr
        if [[ -n "${RADARR_API_KEY:-}" ]]; then
            print_info "Linking Radarr to Bazarr..."
            sed -i "s/use_radarr: false/use_radarr: true/" "$config_file"
            # Update radarr section
            sed -i "/^radarr:/,/^[a-z]/ {
                s/apikey: .*/apikey: ${RADARR_API_KEY}/
                s/ip: .*/ip: radarr/
            }" "$config_file"
            report_log "success" "Radarr linked"
        fi

        # Restart Bazarr
        docker compose up -d bazarr > /dev/null 2>&1 || true
        sleep 3
    else
        report_log "warning" "Bazarr config file not found - manual configuration required"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
