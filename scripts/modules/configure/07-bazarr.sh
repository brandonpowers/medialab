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
            # Bazarr stores an unsalted hex MD5 of the password (still true in 1.6).
            local pass_hash
            pass_hash=$(printf '%s' "$admin_pass" | md5sum | cut -d' ' -f1)

            # Scoped to the auth: section. A file-wide edit would also rewrite
            # the username/password/type keys of ~15 providers, Plex, Postgres
            # and the proxy (Bazarr then resets proxy.type on start).
            if yaml_set_section_value "$config_file" auth type form raw \
                && yaml_set_section_value "$config_file" auth username "$admin_user" \
                && yaml_set_section_value "$config_file" auth password "$pass_hash"; then
                report_log "success" "Forms authentication configured for user: $admin_user"
            else
                report_log "warning" "Could not find Bazarr's auth settings - configure login manually"
            fi
        fi

        # Enable and configure Sonarr
        if [[ -n "${SONARR_API_KEY:-}" ]]; then
            print_info "Linking Sonarr to Bazarr..."
            # Quoted so a key of only digits stays a string (Bazarr's validator
            # would otherwise reset it to empty).
            if yaml_set_section_value "$config_file" general use_sonarr true raw \
                && yaml_set_section_value "$config_file" sonarr apikey "${SONARR_API_KEY}" \
                && yaml_set_section_value "$config_file" sonarr ip sonarr; then
                report_log "success" "Sonarr linked"
            else
                report_log "warning" "Could not find Bazarr's Sonarr settings - link manually"
            fi
        fi

        # Enable and configure Radarr
        if [[ -n "${RADARR_API_KEY:-}" ]]; then
            print_info "Linking Radarr to Bazarr..."
            # Quoted so a key of only digits stays a string (Bazarr's validator
            # would otherwise reset it to empty).
            if yaml_set_section_value "$config_file" general use_radarr true raw \
                && yaml_set_section_value "$config_file" radarr apikey "${RADARR_API_KEY}" \
                && yaml_set_section_value "$config_file" radarr ip radarr; then
                report_log "success" "Radarr linked"
            else
                report_log "warning" "Could not find Bazarr's Radarr settings - link manually"
            fi
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
