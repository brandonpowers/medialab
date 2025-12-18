#!/bin/bash
#
# 05-create-directories.sh - Create service data directories
# Sets up all required directories with proper ownership
#
# Usage:
#   ./05-create-directories.sh [--json]
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --json) OUTPUT_MODE="json" ;;
    esac
done

# ============================================
# MAIN
# ============================================

main() {
    init_progress "Create Directories" 3
    local project_root
    project_root=$(get_project_root)

    # Load environment
    load_env "$project_root/.env"

    local puid=${PUID:-1000}
    local pgid=${PGID:-1000}

    # Step 1: Create service directories
    report_progress 1 3 "Creating service data directories..."

    local dirs=(
        "data/homepage/config"
        "data/jellyfin/config"
        "data/jellyfin/cache"
        "data/jellyseerr/config"
        "data/sonarr/config"
        "data/radarr/config"
        "data/lidarr/config"
        "data/prowlarr/config"
        "data/bazarr/config"
        "data/recyclarr/config"
        "data/recyclarr/config/cache"
        "data/qbittorrent/config"
        "data/sabnzbd/config"
        "data/tdarr/server"
        "data/tdarr/configs"
        "data/tdarr/logs"
        "data/tdarr/temp"
        "data/arm/config"
        "data/arm/home"
        "data/arm/home/db"
        "data/arm/home/logs"
    )

    local created=0
    local existed=0

    for dir in "${dirs[@]}"; do
        local full_path="$project_root/$dir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            ((created++)) || true
        else
            ((existed++)) || true
        fi
    done

    report_log "success" "Created $created directories ($existed already existed)"
    report_progress 1 3 "Service directories ready" "complete"

    # Step 2: Set ownership
    report_progress 2 3 "Setting directory ownership (${puid}:${pgid})..."

    # Set ownership on all data directories
    # This ensures containers can write to their config directories
    local ownership_errors=0

    for dir in "${dirs[@]}"; do
        local full_path="$project_root/$dir"
        if [[ -d "$full_path" ]]; then
            if ! chown -R "${puid}:${pgid}" "$full_path" 2>/dev/null; then
                ((ownership_errors++)) || true
            fi
        fi
    done

    if [[ "$ownership_errors" -gt 0 ]]; then
        report_log "warning" "Could not set ownership on $ownership_errors directories (may need sudo)"
    else
        report_log "success" "All directories owned by ${puid}:${pgid}"
    fi

    # ARM config file permissions for web UI write access
    if [[ -f "$project_root/data/arm/config/arm.yaml" ]]; then
        chmod 664 "$project_root/data/arm/config/arm.yaml" 2>/dev/null || true
    fi

    report_progress 2 3 "Ownership configured" "complete"

    # Step 3: Copy config files if needed
    report_progress 3 3 "Copying configuration files..."

    # Copy recyclarr.yml if it doesn't exist
    if [[ -f "$project_root/config/recyclarr.yml" ]]; then
        if [[ ! -f "$project_root/data/recyclarr/config/recyclarr.yml" ]]; then
            cp "$project_root/config/recyclarr.yml" "$project_root/data/recyclarr/config/"
            report_log "success" "Copied recyclarr.yml"
        fi
    fi

    report_progress 3 3 "Configuration files ready" "complete"

    finish_progress "complete" "All directories created"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        echo "{\"created\": $created, \"existed\": $existed, \"total\": ${#dirs[@]}}"
    fi
}

main "$@"
