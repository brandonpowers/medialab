#!/bin/bash
#
# arm-fix-ownership.sh - Fix file ownership after ARM rip completes
#
# Called by ARM via BASH_SCRIPT setting after each rip.
# ARM/MakeMKV creates files as root, this fixes ownership so Tdarr can process them.
#
# Arguments (from ARM notification system):
#   $1 - Title (e.g., "ARM notification")
#   $2 - Body (e.g., "Rip completed for Movie Name")
#
# Container paths:
#   /home/arm/movies = ${MEDIA_ROOT} on host (contains movies/ and tv/ subdirs)
#   /home/arm/media = ${MEDIA_ROOT}/arm on host (raw/transcode during ripping)
#

# Log function
log() {
    echo "[fix-ownership] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log "Starting ownership fix (triggered by: $1 - $2)"

# Get target UID/GID from environment or default to 1000
TARGET_UID="${ARM_UID:-1000}"
TARGET_GID="${ARM_GID:-1000}"

# Directories to fix (inside container)
# Include completed media directories AND raw/transcode working directories
MEDIA_DIRS="/home/arm/movies/movies /home/arm/movies/tv /home/arm/media/raw /home/arm/media/transcode"

# Find and fix any root-owned files/directories
for dir in $MEDIA_DIRS; do
    if [ -d "$dir" ]; then
        # Count files to fix
        count=$(find "$dir" -user root 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            log "Fixing ownership on $count items in $dir"
            find "$dir" -user root -exec chown "${TARGET_UID}:${TARGET_GID}" {} + 2>/dev/null
            log "Ownership fixed in $dir"
        else
            log "No root-owned files in $dir"
        fi
    fi
done

# Clean up empty directories in transcode (from failed/aborted rips)
if [ -d "/home/arm/media/transcode" ]; then
    empty_count=$(find /home/arm/media/transcode -type d -empty 2>/dev/null | wc -l)
    if [ "$empty_count" -gt 0 ]; then
        log "Cleaning $empty_count empty transcode directories"
        find /home/arm/media/transcode -type d -empty -delete 2>/dev/null || true
    fi
fi

log "Ownership fix complete"
