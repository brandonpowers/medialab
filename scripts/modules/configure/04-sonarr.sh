#!/bin/bash
#
# 04-sonarr.sh - Configure Sonarr TV show manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Sonarr"
MODULE_STEP=4
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Sonarr"

    sleep 3
    local api_key
    api_key=$(get_api_key "sonarr")

    if [[ -z "$api_key" ]]; then
        report_log "error" "Failed to get Sonarr API key"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "warning"
        return 1
    fi

    report_log "success" "Sonarr API key: $api_key"
    update_env_api_key "SONARR_API_KEY" "$api_key"
    export SONARR_API_KEY="$api_key"

    # Configure authentication
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    if [[ -n "$admin_pass" ]]; then
        print_info "Configuring Sonarr authentication..."
        configure_arr_auth "http://localhost:8989" "$api_key" "$admin_user" "$admin_pass" "v3"
    fi

    # Add root folder
    add_root_folder "http://localhost:8989" "$api_key" "/media/tv"

    # Create 4K Preferred quality profile
    # This profile prefers 4K but accepts 1080p as fallback for content not available in 4K
    print_info "Creating 4K Preferred quality profile..."
    local schema formats items profile_body
    schema=$(api_get "http://localhost:8989/api/v3/qualityprofile/schema" "$api_key" 2>/dev/null)
    if [[ -n "$schema" ]]; then
        # Get format items and modify quality items to enable 1080p and 4K
        formats=$(echo "$schema" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('formatItems', [])))" 2>/dev/null)
        items=$(echo "$schema" | python3 -c "
import sys,json
schema = json.load(sys.stdin)
items = schema.get('items', [])
# Enable 1080p and 4K qualities
for item in items:
    q = item.get('quality', {})
    qid = q.get('id', 0)
    # Enable 1080p: HDTV-1080p(9), Bluray-1080p(7), Bluray-1080p Remux(20)
    # Enable 4K: HDTV-2160p(16), Bluray-2160p(19), Bluray-2160p Remux(21)
    if qid in [9, 7, 20, 16, 19, 21]:
        item['allowed'] = True
    elif item.get('id') in [1002, 1003]:  # WEB 1080p/2160p groups
        item['allowed'] = True
        for sub in item.get('items', []):
            sub['allowed'] = True
    else:
        item['allowed'] = False
        for sub in item.get('items', []):
            sub['allowed'] = False
print(json.dumps(items))
" 2>/dev/null)
        profile_body=$(cat <<EOF
{
  "name": "4K Preferred",
  "upgradeAllowed": true,
  "cutoff": 21,
  "minUpgradeFormatScore": 1,
  "cutoffFormatScore": 0,
  "minFormatScore": 0,
  "items": ${items},
  "formatItems": ${formats}
}
EOF
)
        api_post "http://localhost:8989/api/v3/qualityprofile" "$profile_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "4K Preferred quality profile created" || report_log "info" "4K Preferred profile may already exist"
    else
        report_log "warning" "Could not get quality schema - skipping 4K profile creation"
    fi

    # Determine qBittorrent priority
    local qbit_priority=1
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        qbit_priority=2
    fi

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Sonarr (priority ${qbit_priority})..."
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
        {"name": "tvCategory", "value": "tv"},
        {"name": "recentTvPriority", "value": 0},
        {"name": "olderTvPriority", "value": 0}
    ],
    "implementationName": "qBittorrent",
    "implementation": "QBittorrent",
    "configContract": "QBittorrentSettings",
    "tags": []
}
EOF
)
    api_post "http://localhost:8989/api/v3/downloadclient" "$qbit_body" "$api_key" > /dev/null 2>&1 && \
        report_log "success" "qBittorrent added" || report_log "info" "qBittorrent may already exist"

    # Add SABnzbd if configured
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        print_info "Adding SABnzbd to Sonarr (priority 1 - primary)..."
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
        {"name": "tvCategory", "value": "tv"}
    ],
    "implementationName": "SABnzbd",
    "implementation": "Sabnzbd",
    "configContract": "SabnzbdSettings",
    "tags": []
}
EOF
)
        api_post "http://localhost:8989/api/v3/downloadclient" "$sabnzbd_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "SABnzbd added" || report_log "info" "SABnzbd may already exist"

        # Add remote path mapping for SABnzbd downloads
        # SABnzbd uses /downloads internally, but Sonarr sees it as /media/downloads
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
        api_post "http://localhost:8989/api/v3/remotepathmapping" "$pathmapping_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "SABnzbd path mapping added" || report_log "info" "Path mapping may already exist"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
