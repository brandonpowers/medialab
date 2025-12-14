#!/bin/bash
#
# 01-wait-services.sh - Wait for critical services to be ready
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Wait for Services"
MODULE_STEP=1
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"

    # Load environment
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
    else
        report_log "error" ".env file not found"
        exit 1
    fi

    # Ensure all required media directories exist
    local media_root="${MEDIA_ROOT:-/mnt/media}"
    local puid="${PUID:-1000}"
    local pgid="${PGID:-1000}"

    local media_dirs=("movies" "tv" "music" "downloads/complete" "downloads/incomplete" "downloads/watch" "transcode" "arm")
    local dirs_created=false

    for dir in "${media_dirs[@]}"; do
        if [[ ! -d "$media_root/$dir" ]]; then
            mkdir -p "$media_root/$dir"
            chown "${puid}:${pgid}" "$media_root/$dir"
            report_log "info" "Created missing directory: $media_root/$dir"
            dirs_created=true
        fi
    done

    # If we created any directories, restart containers so they can see the new mounts
    if [[ "$dirs_created" == "true" ]]; then
        report_log "info" "Restarting containers to apply new directory mappings..."
        docker compose restart sonarr radarr lidarr bazarr tdarr > /dev/null 2>&1 || true
        sleep 5
    fi

    print_section "Waiting for Services to Start"

    # Critical services - must be ready
    wait_for_service "Prowlarr" "http://localhost:9696/ping" 30 2 || exit 1
    wait_for_service "Sonarr" "http://localhost:8989/ping" 30 2 || exit 1
    wait_for_service "Radarr" "http://localhost:7878/ping" 30 2 || exit 1
    wait_for_service "Lidarr" "http://localhost:8686/ping" 30 2 || exit 1
    wait_for_service "qBittorrent" "http://localhost:8080" 30 2 || exit 1

    # Optional services - continue if not ready
    wait_for_service "Bazarr" "http://localhost:6767" 15 2 || print_info "Bazarr will need manual configuration"
    wait_for_service "SABnzbd" "http://localhost:8085" 15 2 || print_info "SABnzbd will need manual configuration"
    wait_for_service "Jellyfin" "http://localhost:8096/health" 15 2 || print_info "Jellyfin will need manual configuration"
    wait_for_service "Jellyseerr" "http://localhost:5055" 15 2 || print_info "Jellyseerr will need manual configuration"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
