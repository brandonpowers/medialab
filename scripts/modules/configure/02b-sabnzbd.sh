#!/bin/bash
#
# 02b-sabnzbd.sh - Configure SABnzbd Usenet downloader
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure SABnzbd"
MODULE_STEP=2
MODULE_TOTAL=13

SABNZBD_URL="http://localhost:8085"

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    # Get SABnzbd API key
    local api_key="${SABNZBD_API_KEY:-}"
    if [[ -z "$api_key" ]]; then
        api_key=$(get_api_key "sabnzbd")
    fi

    if [[ -z "$api_key" ]]; then
        report_log "warning" "SABnzbd API key not found - skipping configuration"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    print_section "Configuring SABnzbd"

    # Configure download categories
    print_info "Configuring download categories..."
    for category in tv movies music; do
        curl -s "${SABNZBD_URL}/api" \
            -d "mode=set_config" \
            -d "apikey=${api_key}" \
            -d "section=categories" \
            -d "keyword=${category}" \
            -d "name=${category}" > /dev/null 2>&1
    done
    report_log "success" "Download categories configured"

    # Configure Usenet server if settings are provided
    if [[ -n "${USENET_HOST:-}" && -n "${USENET_USER:-}" ]]; then
        print_info "Adding Usenet server: ${USENET_HOST}..."

        local ssl_val="1"
        if [[ "${USENET_SSL:-true}" != "true" ]]; then
            ssl_val="0"
        fi

        # Add Usenet server
        curl -s "${SABNZBD_URL}/api" \
            -d "mode=set_config" \
            -d "apikey=${api_key}" \
            -d "section=servers" \
            -d "keyword=usenet_server" \
            -d "servers[usenet_server][host]=${USENET_HOST}" \
            -d "servers[usenet_server][port]=${USENET_PORT:-563}" \
            -d "servers[usenet_server][username]=${USENET_USER}" \
            -d "servers[usenet_server][password]=${USENET_PASS:-}" \
            -d "servers[usenet_server][connections]=${USENET_CONNECTIONS:-30}" \
            -d "servers[usenet_server][ssl]=${ssl_val}" \
            -d "servers[usenet_server][ssl_verify]=2" \
            -d "servers[usenet_server][enable]=1" \
            -d "servers[usenet_server][priority]=0" > /dev/null 2>&1 && \
            report_log "success" "Usenet server added: ${USENET_HOST}" || \
            report_log "warning" "Failed to add Usenet server"
    else
        report_log "info" "No Usenet server configured - add one at ${SABNZBD_URL}"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
