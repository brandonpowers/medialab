#!/bin/bash
#
# 08-link-prowlarr.sh - Link Prowlarr to *arr apps
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Link Prowlarr to Apps"
MODULE_STEP=8
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    local prowlarr_key="${PROWLARR_API_KEY:-}"
    if [[ -z "$prowlarr_key" ]]; then
        prowlarr_key=$(get_api_key "prowlarr")
    fi

    if [[ -z "$prowlarr_key" ]]; then
        report_log "warning" "Prowlarr API key not found - skipping app linking"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    print_section "Linking Prowlarr to *arr Apps"

    # Get API keys
    local sonarr_key="${SONARR_API_KEY:-$(get_api_key sonarr)}"
    local radarr_key="${RADARR_API_KEY:-$(get_api_key radarr)}"
    local lidarr_key="${LIDARR_API_KEY:-$(get_api_key lidarr)}"

    # Link Sonarr
    if [[ -n "$sonarr_key" ]]; then
        print_info "Linking Sonarr to Prowlarr..."
        local sonarr_body
        sonarr_body=$(cat <<EOF
{
    "name": "Sonarr",
    "syncLevel": "fullSync",
    "fields": [
        {"name": "prowlarrUrl", "value": "http://prowlarr:9696"},
        {"name": "baseUrl", "value": "http://sonarr:8989"},
        {"name": "apiKey", "value": "${sonarr_key}"},
        {"name": "syncCategories", "value": [5000, 5010, 5020, 5030, 5040, 5045, 5050]}
    ],
    "implementationName": "Sonarr",
    "implementation": "Sonarr",
    "configContract": "SonarrSettings",
    "tags": []
}
EOF
)
        api_post "http://localhost:9696/api/v1/applications" "$sonarr_body" "$prowlarr_key" > /dev/null 2>&1 && \
            report_log "success" "Sonarr linked to Prowlarr" || report_log "info" "Sonarr may already be linked"
    fi

    # Link Radarr
    if [[ -n "$radarr_key" ]]; then
        print_info "Linking Radarr to Prowlarr..."
        local radarr_body
        radarr_body=$(cat <<EOF
{
    "name": "Radarr",
    "syncLevel": "fullSync",
    "fields": [
        {"name": "prowlarrUrl", "value": "http://prowlarr:9696"},
        {"name": "baseUrl", "value": "http://radarr:7878"},
        {"name": "apiKey", "value": "${radarr_key}"},
        {"name": "syncCategories", "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]}
    ],
    "implementationName": "Radarr",
    "implementation": "Radarr",
    "configContract": "RadarrSettings",
    "tags": []
}
EOF
)
        api_post "http://localhost:9696/api/v1/applications" "$radarr_body" "$prowlarr_key" > /dev/null 2>&1 && \
            report_log "success" "Radarr linked to Prowlarr" || report_log "info" "Radarr may already be linked"
    fi

    # Link Lidarr
    if [[ -n "$lidarr_key" ]]; then
        print_info "Linking Lidarr to Prowlarr..."
        local lidarr_body
        lidarr_body=$(cat <<EOF
{
    "name": "Lidarr",
    "syncLevel": "fullSync",
    "fields": [
        {"name": "prowlarrUrl", "value": "http://prowlarr:9696"},
        {"name": "baseUrl", "value": "http://lidarr:8686"},
        {"name": "apiKey", "value": "${lidarr_key}"},
        {"name": "syncCategories", "value": [3000, 3010, 3020, 3030, 3040, 3050, 3060]}
    ],
    "implementationName": "Lidarr",
    "implementation": "Lidarr",
    "configContract": "LidarrSettings",
    "tags": []
}
EOF
)
        api_post "http://localhost:9696/api/v1/applications" "$lidarr_body" "$prowlarr_key" > /dev/null 2>&1 && \
            report_log "success" "Lidarr linked to Prowlarr" || report_log "info" "Lidarr may already be linked"
    fi

    # Trigger sync to push indexers to all linked apps
    print_info "Triggering Prowlarr sync..."
    sleep 2
    api_post "http://localhost:9696/api/v1/applicationsindexersync" "" "$prowlarr_key" > /dev/null 2>&1 && \
        report_log "success" "Indexers synced to all apps" || report_log "warning" "Sync may need to be triggered manually"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
