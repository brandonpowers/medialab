#!/bin/bash
#
# 05-radarr.sh - Configure Radarr movie manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Radarr"
MODULE_STEP=5
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Radarr"

    local api_key
    api_key=$(wait_for_api_key "radarr")

    if [[ -z "$api_key" ]]; then
        report_log "error" "Failed to get Radarr API key"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "warning"
        return 1
    fi

    report_log "success" "Radarr API key: $api_key"
    update_env_api_key "RADARR_API_KEY" "$api_key"
    export RADARR_API_KEY="$api_key"

    # Configure authentication
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    if [[ -n "$admin_pass" ]]; then
        print_info "Configuring Radarr authentication..."
        configure_arr_auth "${RADARR_URL}" "$api_key" "$admin_user" "$admin_pass" "v3"
    fi

    # Add root folder
    add_root_folder "${RADARR_URL}" "$api_key" "/media/movies"

    # Create 4K Preferred quality profile
    # This profile prefers 4K but accepts 1080p as fallback for content not available in 4K
    print_info "Creating 4K Preferred quality profile..."
    local schema formats profile_body
    schema=$(api_get "${RADARR_URL}/api/v3/qualityprofile/schema" "$api_key" 2>/dev/null)
    if [[ -n "$schema" ]]; then
        formats=$(echo "$schema" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('formatItems', [])))" 2>/dev/null)
        profile_body=$(cat <<EOF
{
  "name": "4K Preferred",
  "upgradeAllowed": true,
  "cutoff": 31,
  "minUpgradeFormatScore": 1,
  "cutoffFormatScore": 0,
  "minFormatScore": 0,
  "items": [
    {"quality": {"id": 0, "name": "Unknown"}, "items": [], "allowed": false},
    {"quality": {"id": 24, "name": "WORKPRINT"}, "items": [], "allowed": false},
    {"quality": {"id": 25, "name": "CAM"}, "items": [], "allowed": false},
    {"quality": {"id": 26, "name": "TELESYNC"}, "items": [], "allowed": false},
    {"quality": {"id": 27, "name": "TELECINE"}, "items": [], "allowed": false},
    {"quality": {"id": 29, "name": "REGIONAL"}, "items": [], "allowed": false},
    {"quality": {"id": 28, "name": "DVDSCR"}, "items": [], "allowed": false},
    {"quality": {"id": 1, "name": "SDTV"}, "items": [], "allowed": false},
    {"quality": {"id": 2, "name": "DVD"}, "items": [], "allowed": false},
    {"quality": {"id": 23, "name": "DVD-R"}, "items": [], "allowed": false},
    {"id": 1000, "name": "WEB 480p", "items": [
      {"quality": {"id": 8, "name": "WEBDL-480p"}, "items": [], "allowed": false},
      {"quality": {"id": 12, "name": "WEBRip-480p"}, "items": [], "allowed": false}
    ], "allowed": false},
    {"quality": {"id": 20, "name": "Bluray-480p"}, "items": [], "allowed": false},
    {"quality": {"id": 21, "name": "Bluray-576p"}, "items": [], "allowed": false},
    {"quality": {"id": 4, "name": "HDTV-720p"}, "items": [], "allowed": false},
    {"id": 1001, "name": "WEB 720p", "items": [
      {"quality": {"id": 5, "name": "WEBDL-720p"}, "items": [], "allowed": false},
      {"quality": {"id": 14, "name": "WEBRip-720p"}, "items": [], "allowed": false}
    ], "allowed": false},
    {"quality": {"id": 6, "name": "Bluray-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 9, "name": "HDTV-1080p"}, "items": [], "allowed": true},
    {"id": 1002, "name": "WEB 1080p", "items": [
      {"quality": {"id": 3, "name": "WEBDL-1080p"}, "items": [], "allowed": true},
      {"quality": {"id": 15, "name": "WEBRip-1080p"}, "items": [], "allowed": true}
    ], "allowed": true},
    {"quality": {"id": 7, "name": "Bluray-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 30, "name": "Remux-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 16, "name": "HDTV-2160p"}, "items": [], "allowed": true},
    {"id": 1003, "name": "WEB 2160p", "items": [
      {"quality": {"id": 18, "name": "WEBDL-2160p"}, "items": [], "allowed": true},
      {"quality": {"id": 17, "name": "WEBRip-2160p"}, "items": [], "allowed": true}
    ], "allowed": true},
    {"quality": {"id": 19, "name": "Bluray-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 31, "name": "Remux-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 22, "name": "BR-DISK"}, "items": [], "allowed": false},
    {"quality": {"id": 10, "name": "Raw-HD"}, "items": [], "allowed": false}
  ],
  "formatItems": ${formats}
}
EOF
)
        ensure_resource "4K Preferred quality profile" \
            "${RADARR_URL}/api/v3/qualityprofile" "4K Preferred" "$profile_body" "$api_key" || true
    else
        report_log "warning" "Could not get quality schema - skipping 4K profile creation"
    fi

    # Determine qBittorrent priority
    local qbit_priority=1
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        qbit_priority=2
    fi

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Radarr (priority ${qbit_priority})..."
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
        {"name": "movieCategory", "value": "movies"},
        {"name": "recentMoviePriority", "value": 0},
        {"name": "olderMoviePriority", "value": 0}
    ],
    "implementationName": "qBittorrent",
    "implementation": "QBittorrent",
    "configContract": "QBittorrentSettings",
    "tags": []
}
EOF
)
    ensure_resource "qBittorrent download client" \
        "${RADARR_URL}/api/v3/downloadclient" "qBittorrent" "$qbit_body" "$api_key" || true

    # Add SABnzbd if configured
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        print_info "Adding SABnzbd to Radarr (priority 1 - primary)..."
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
        {"name": "movieCategory", "value": "movies"}
    ],
    "implementationName": "SABnzbd",
    "implementation": "Sabnzbd",
    "configContract": "SabnzbdSettings",
    "tags": []
}
EOF
)
        ensure_resource "SABnzbd download client" \
            "${RADARR_URL}/api/v3/downloadclient" "SABnzbd" "$sabnzbd_body" "$api_key" || true

        # Add remote path mapping for SABnzbd downloads
        # SABnzbd uses /downloads internally, but Radarr sees it as /media/downloads
        print_info "Adding SABnzbd remote path mapping..."
        local pathmapping_body
        pathmapping_body=$(cat <<EOF
{
    "host": "sabnzbd",
    "remotePath": "/downloads/",
    "localPath": "/media/downloads/"
}
EOF
)
        api_post "${RADARR_URL}/api/v3/remotepathmapping" "$pathmapping_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "SABnzbd path mapping added" || report_log "info" "Path mapping may already exist"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
