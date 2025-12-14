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

    sleep 3
    local api_key
    api_key=$(get_api_key "radarr")

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
        configure_arr_auth "http://localhost:7878" "$api_key" "$admin_user" "$admin_pass" "v3"
    fi

    # Add root folder
    add_root_folder "http://localhost:7878" "$api_key" "/media/movies"

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
    api_post "http://localhost:7878/api/v3/downloadclient" "$qbit_body" "$api_key" > /dev/null 2>&1 && \
        report_log "success" "qBittorrent added" || report_log "info" "qBittorrent may already exist"

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
        api_post "http://localhost:7878/api/v3/downloadclient" "$sabnzbd_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "SABnzbd added" || report_log "info" "SABnzbd may already exist"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
