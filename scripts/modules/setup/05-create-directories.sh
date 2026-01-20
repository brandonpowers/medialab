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
    init_progress "Create Directories" 4
    local project_root
    project_root=$(get_project_root)

    # Load environment
    load_env "$project_root/.env"

    local puid=${PUID:-1000}
    local pgid=${PGID:-1000}
    local media_root="${MEDIA_ROOT:-/mnt/media}"

    # Step 1: Create service directories
    report_progress 1 4 "Creating service data directories..."

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
    report_progress 1 4 "Service directories ready" "complete"

    # Step 1b: Create ARM media directories on external drive
    # These are separate from service config dirs - they hold actual ripped media
    # ARM/MakeMKV runs as root inside the container, so files get created as root
    # We need proper permissions and ACLs so brandon can access them
    local arm_media_dirs=(
        "$media_root/arm/raw"        # Raw disc backups during ripping
        "$media_root/arm/transcode"  # Transcoding workspace
        "$media_root/arm/completed"  # Completed rips before moving to final location
        "$media_root/arm/movies"     # Additional output location
    )

    for dir in "${arm_media_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            report_log "success" "Created ARM media directory: $dir"
        fi
        # Always ensure correct ownership and permissions (775 = rwxrwxr-x)
        chown "${puid}:${pgid}" "$dir" 2>/dev/null || true
        chmod 775 "$dir" 2>/dev/null || true
    done

    # Step 2: Set ownership
    report_progress 2 4 "Setting directory ownership (${puid}:${pgid})..."

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

    report_progress 2 4 "Ownership configured" "complete"

    # Step 3: Copy config files if needed
    report_progress 3 4 "Copying configuration files..."

    # Copy recyclarr.yml if it doesn't exist
    if [[ -f "$project_root/config/recyclarr.yml" ]]; then
        if [[ ! -f "$project_root/data/recyclarr/config/recyclarr.yml" ]]; then
            cp "$project_root/config/recyclarr.yml" "$project_root/data/recyclarr/config/"
            report_log "success" "Copied recyclarr.yml"
        fi
    fi

    report_progress 3 4 "Configuration files ready" "complete"

    # Step 4: Ensure media directory ownership
    # Note: Complex ACL inheritance was removed - our custom arm-wrapper.sh now uses gosu
    # to run the ripper as the arm user (UID 1000), so files are created with correct ownership.
    report_progress 4 4 "Verifying media directory ownership..."

    local media_dirs=(
        "$media_root"
        "$media_root/movies"
        "$media_root/tv"
        "$media_root/music"
        "$media_root/downloads"
        "$media_root/arm"
        "$media_root/unidentified"  # ARM output for discs that can't be auto-identified
    )

    local fixed_count=0
    for dir in "${media_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Fix ownership if not already correct
            if [[ "$(stat -c '%u' "$dir" 2>/dev/null)" != "$puid" ]]; then
                chown "${puid}:${pgid}" "$dir" 2>/dev/null && ((fixed_count++)) || true
            fi
            chmod 775 "$dir" 2>/dev/null || true
        fi
    done

    if [[ "$fixed_count" -gt 0 ]]; then
        report_log "success" "Fixed ownership on $fixed_count media directories"
    else
        report_log "success" "All media directories have correct ownership"
    fi
    report_progress 4 4 "Media directories ready" "complete"

    finish_progress "complete" "All directories created"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        echo "{\"created\": $created, \"existed\": $existed, \"total\": ${#dirs[@]}}"
    fi
}

main "$@"
