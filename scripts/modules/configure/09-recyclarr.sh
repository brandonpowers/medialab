#!/bin/bash
#
# 09-recyclarr.sh - Run Recyclarr to sync quality profiles
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Sync Quality Profiles"
MODULE_STEP=9
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    local sonarr_key="${SONARR_API_KEY:-$(get_api_key sonarr)}"
    local radarr_key="${RADARR_API_KEY:-$(get_api_key radarr)}"

    if [[ -z "$sonarr_key" ]] || [[ -z "$radarr_key" ]]; then
        report_log "warning" "Missing API keys - skipping Recyclarr sync"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    print_section "Syncing Quality Profiles with Recyclarr"

    local project_root
    project_root=$(get_project_root)

    # Ensure recyclarr config directory exists
    local config_dir="${project_root}/data/recyclarr/config"
    local cache_dir="${config_dir}/cache"
    mkdir -p "$cache_dir"

    # Copy recyclarr.yml config if it doesn't exist
    if [[ ! -f "${config_dir}/recyclarr.yml" ]]; then
        if [[ -f "${project_root}/config/recyclarr.yml" ]]; then
            cp "${project_root}/config/recyclarr.yml" "${config_dir}/recyclarr.yml"
            report_log "success" "Copied recyclarr.yml configuration"
        else
            report_log "warning" "config/recyclarr.yml not found in project"
            print_info "Skipping Recyclarr sync"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            return 0
        fi
    fi

    # Fix ownership if running as root
    if [[ "$(id -u)" == "0" ]]; then
        chown -R "${PUID:-1000}:${PGID:-1000}" "${project_root}/data/recyclarr"
    fi

    # Run Recyclarr
    if [[ -f "${config_dir}/recyclarr.yml" ]]; then
        print_info "Running Recyclarr sync..."
        if docker compose run --rm \
            -e SONARR_API_KEY="$sonarr_key" \
            -e RADARR_API_KEY="$radarr_key" \
            recyclarr sync 2>&1; then
            report_log "success" "Quality profiles synced successfully"
            print_info "Custom formats from TRaSH Guides have been applied"
        else
            report_log "warning" "Recyclarr sync failed - you may need to run it manually later"
            print_info "Run: docker compose run --rm recyclarr sync"
        fi
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
