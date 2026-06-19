#!/bin/bash
#
# 06-lidarr.sh - Configure Lidarr music manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Lidarr"
MODULE_STEP=6
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Lidarr"

    local api_key
    api_key=$(wait_for_api_key "lidarr")

    if [[ -z "$api_key" ]]; then
        report_log "error" "Failed to get Lidarr API key"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "warning"
        return 1
    fi

    report_log "success" "Lidarr API key: $api_key"
    update_env_api_key "LIDARR_API_KEY" "$api_key"
    export LIDARR_API_KEY="$api_key"

    # Configure authentication (Lidarr uses v1 API)
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    if [[ -n "$admin_pass" ]]; then
        print_info "Configuring Lidarr authentication..."
        configure_arr_auth "${LIDARR_URL}" "$api_key" "$admin_user" "$admin_pass" "v1"
    fi

    # Get profile IDs for root folder
    print_info "Adding root folder to Lidarr..."
    local quality_profile
    quality_profile=$(json_first_id "$(api_get "${LIDARR_URL}/api/v1/qualityprofile" "$api_key")" "1")
    local metadata_profile
    metadata_profile=$(json_first_id "$(api_get "${LIDARR_URL}/api/v1/metadataprofile" "$api_key")" "1")

    # Add root folder (Lidarr v1 API)
    local root_body
    root_body=$(cat <<EOF
{
    "path": "/media/music",
    "name": "Music",
    "defaultQualityProfileId": ${quality_profile:-1},
    "defaultMetadataProfileId": ${metadata_profile:-1}
}
EOF
)
    api_post "${LIDARR_URL}/api/v1/rootfolder" "$root_body" "$api_key" > /dev/null 2>&1 && \
        report_log "success" "Root folder added" || report_log "info" "Root folder may already exist"

    # Determine qBittorrent priority
    local qbit_priority=1
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        qbit_priority=2
    fi

    # Add qBittorrent download client (Lidarr uses v1 API)
    print_info "Adding qBittorrent to Lidarr (priority ${qbit_priority})..."
    local qbit_user="${QBIT_USER:-admin}"
    local qbit_pass="${QBIT_PASS:-adminadmin}"

    local qbit_body
    qbit_body=$(cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": ${qbit_priority},
    "removeCompletedDownloads": true,
    "removeFailedDownloads": true,
    "name": "qBittorrent",
    "fields": [
        {"name": "host", "value": "qbittorrent"},
        {"name": "port", "value": 8080},
        {"name": "urlBase", "value": ""},
        {"name": "username", "value": "${qbit_user}"},
        {"name": "password", "value": "${qbit_pass}"},
        {"name": "musicCategory", "value": "music"}
    ],
    "implementationName": "qBittorrent",
    "implementation": "QBittorrent",
    "configContract": "QBittorrentSettings",
    "tags": []
}
EOF
)
    ensure_resource "qBittorrent download client" \
        "${LIDARR_URL}/api/v1/downloadclient" "qBittorrent" "$qbit_body" "$api_key" || true

    # Add SABnzbd if configured
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        print_info "Adding SABnzbd to Lidarr (priority 1 - primary)..."
        local sabnzbd_body
        sabnzbd_body=$(cat <<EOF
{
    "enable": true,
    "protocol": "usenet",
    "priority": 1,
    "removeCompletedDownloads": true,
    "removeFailedDownloads": true,
    "name": "SABnzbd",
    "fields": [
        {"name": "host", "value": "sabnzbd"},
        {"name": "port", "value": 8080},
        {"name": "apiKey", "value": "${SABNZBD_API_KEY}"},
        {"name": "musicCategory", "value": "music"}
    ],
    "implementationName": "SABnzbd",
    "implementation": "Sabnzbd",
    "configContract": "SabnzbdSettings",
    "tags": []
}
EOF
)
        ensure_resource "SABnzbd download client" \
            "${LIDARR_URL}/api/v1/downloadclient" "SABnzbd" "$sabnzbd_body" "$api_key" || true
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
