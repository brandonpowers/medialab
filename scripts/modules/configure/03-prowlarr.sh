#!/bin/bash
#
# 03-prowlarr.sh - Configure Prowlarr indexer manager
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Prowlarr"
MODULE_STEP=3
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Prowlarr"

    # Wait for API key to be generated
    sleep 5
    local api_key
    api_key=$(get_api_key "prowlarr")

    if [[ -z "$api_key" ]]; then
        report_log "error" "Failed to get Prowlarr API key"
        print_info "Please configure Prowlarr manually at http://localhost:9696"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "warning"
        return 1
    fi

    report_log "success" "Prowlarr API key: $api_key"
    update_env_api_key "PROWLARR_API_KEY" "$api_key"
    export PROWLARR_API_KEY="$api_key"

    # Configure authentication (Prowlarr uses v1 API)
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    if [[ -n "$admin_pass" ]]; then
        print_info "Configuring Prowlarr authentication..."
        configure_arr_auth "http://localhost:9696" "$api_key" "$admin_user" "$admin_pass" "v1"
    fi

    # Create FlareSolverr tag
    print_info "Creating FlareSolverr tag..."
    local tag_id
    tag_id=$(api_post "http://localhost:9696/api/v1/tag" '{"label": "flaresolverr"}' "$api_key" 2>/dev/null | grep -oP '"id":\s*\K\d+' || echo "")

    if [[ -z "$tag_id" ]]; then
        # Tag might already exist, get its ID
        tag_id=$(api_get "http://localhost:9696/api/v1/tag" "$api_key" 2>/dev/null | grep -oP '"id":\s*\K\d+' | head -1 || echo "1")
    fi

    # Add FlareSolverr proxy
    print_info "Adding FlareSolverr to Prowlarr..."
    local flaresolverr_body
    flaresolverr_body=$(cat <<EOF
{
    "name": "FlareSolverr",
    "fields": [
        {"name": "host", "value": "http://flaresolverr:8191"},
        {"name": "requestTimeout", "value": 120}
    ],
    "implementationName": "FlareSolverr",
    "implementation": "FlareSolverr",
    "configContract": "FlareSolverrSettings",
    "tags": [${tag_id:-1}]
}
EOF
)
    api_post "http://localhost:9696/api/v1/indexerproxy" "$flaresolverr_body" "$api_key" > /dev/null 2>&1 && \
        report_log "success" "FlareSolverr added to Prowlarr" || report_log "info" "FlareSolverr may already exist"

    # Add public indexers
    print_info "Adding public torrent indexers..."

    add_public_indexer "$api_key" "1337x" "1337x" "[${tag_id:-1}]"
    add_public_indexer "$api_key" "EZTV" "eztv" "[]"
    add_public_indexer "$api_key" "YTS" "yts" "[]"
    add_public_indexer "$api_key" "LimeTorrents" "limetorrents" "[]"
    add_public_indexer "$api_key" "The Pirate Bay" "thepiratebay" "[]"

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Prowlarr..."
    local qbit_user="${QBIT_USER:-admin}"
    local qbit_pass="${QBIT_PASS:-adminadmin}"

    local qbit_body
    qbit_body=$(cat <<EOF
{
    "enable": true,
    "protocol": "torrent",
    "priority": 1,
    "name": "qBittorrent",
    "fields": [
        {"name": "host", "value": "qbittorrent"},
        {"name": "port", "value": 8080},
        {"name": "urlBase", "value": ""},
        {"name": "username", "value": "${qbit_user}"},
        {"name": "password", "value": "${qbit_pass}"},
        {"name": "category", "value": "prowlarr"},
        {"name": "recentTvPriority", "value": 0},
        {"name": "olderTvPriority", "value": 0},
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
    api_post "http://localhost:9696/api/v1/downloadclient" "$qbit_body" "$api_key" > /dev/null 2>&1 && \
        report_log "success" "qBittorrent added to Prowlarr" || report_log "info" "qBittorrent may already exist"

    # Add SABnzbd download client if configured
    if [[ -n "${SABNZBD_API_KEY:-}" ]]; then
        print_info "Adding SABnzbd to Prowlarr..."
        local sab_body
        sab_body=$(cat <<EOF
{
    "enable": true,
    "protocol": "usenet",
    "priority": 1,
    "name": "SABnzbd",
    "fields": [
        {"name": "host", "value": "sabnzbd"},
        {"name": "port", "value": 8080},
        {"name": "apiKey", "value": "${SABNZBD_API_KEY}"},
        {"name": "category", "value": "prowlarr"},
        {"name": "recentTvPriority", "value": 0},
        {"name": "olderTvPriority", "value": 0},
        {"name": "recentMoviePriority", "value": 0},
        {"name": "olderMoviePriority", "value": 0}
    ],
    "implementationName": "SABnzbd",
    "implementation": "Sabnzbd",
    "configContract": "SabnzbdSettings",
    "tags": []
}
EOF
)
        api_post "http://localhost:9696/api/v1/downloadclient" "$sab_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "SABnzbd added to Prowlarr" || report_log "info" "SABnzbd may already exist"
    fi

    # Add NZB indexer if configured
    if [[ -n "${NZB_INDEXER_API_KEY:-}" && -n "${NZB_INDEXER_URL:-}" ]]; then
        print_info "Adding NZB indexer: ${NZB_INDEXER_TYPE:-nzbgeek}..."

        local nzb_name nzb_implementation nzb_config_contract
        case "${NZB_INDEXER_TYPE:-nzbgeek}" in
            nzbgeek)
                nzb_name="NZBgeek"
                nzb_implementation="Newznab"
                nzb_config_contract="NewznabSettings"
                ;;
            drunkenslug)
                nzb_name="DrunkenSlug"
                nzb_implementation="Newznab"
                nzb_config_contract="NewznabSettings"
                ;;
            nzbfinder)
                nzb_name="NZBFinder"
                nzb_implementation="Newznab"
                nzb_config_contract="NewznabSettings"
                ;;
            *)
                nzb_name="${NZB_INDEXER_TYPE}"
                nzb_implementation="Newznab"
                nzb_config_contract="NewznabSettings"
                ;;
        esac

        local nzb_body
        nzb_body=$(cat <<EOF
{
    "enable": true,
    "redirect": true,
    "protocol": "usenet",
    "priority": 25,
    "appProfileId": 1,
    "name": "${nzb_name}",
    "fields": [
        {"name": "baseUrl", "value": "${NZB_INDEXER_URL}"},
        {"name": "apiPath", "value": "/api"},
        {"name": "apiKey", "value": "${NZB_INDEXER_API_KEY}"},
        {"name": "categories", "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 5000, 5010, 5020, 5030, 5040, 5050, 3000, 3010, 3020, 3030, 3040]},
        {"name": "vipExpiration", "value": ""}
    ],
    "implementationName": "${nzb_implementation}",
    "implementation": "${nzb_implementation}",
    "configContract": "${nzb_config_contract}",
    "tags": []
}
EOF
)
        api_post "http://localhost:9696/api/v1/indexer" "$nzb_body" "$api_key" > /dev/null 2>&1 && \
            report_log "success" "${nzb_name} indexer added to Prowlarr" || report_log "info" "${nzb_name} may already exist"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
