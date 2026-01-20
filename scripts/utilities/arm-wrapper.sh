#!/bin/bash
#
# arm-wrapper.sh - Custom ARM wrapper with proper privilege dropping
#
# This replaces the upstream docker_arm_wrapper.sh to fix the root ownership issue.
# The upstream script runs the ripper as root, causing all MKV files to be owned
# by root:root. This version uses gosu to drop privileges to the arm user.
#
# Mounted into container at: /opt/arm/scripts/docker/docker_arm_wrapper.sh
#

DEVNAME=$1

# Exit early if no device provided
if [[ -z "$DEVNAME" ]]; then
    echo "[arm-wrapper] No device provided, exiting"
    exit 1
fi

# Log startup
echo "[arm-wrapper] Starting ARM ripper for device: $DEVNAME"
echo "[arm-wrapper] Running as: $(id)"

# Wait for ARM services to be ready
sleep 5

# Get arm user UID from environment or default
ARM_UID="${ARM_UID:-1000}"
ARM_GID="${ARM_GID:-1000}"

# Ensure the arm user exists and has correct UID/GID
# (ARM container image should already have this, but verify)
if ! id arm &>/dev/null; then
    echo "[arm-wrapper] ERROR: arm user does not exist"
    exit 1
fi

# Ensure arm user owns necessary directories before ripping
# This prevents "Permission ERROR" at startup
for dir in /home/arm/media/raw /home/arm/media/transcode /home/arm/media/completed /home/arm/movies/unidentified; do
    if [[ -d "$dir" ]]; then
        chown "$ARM_UID:$ARM_GID" "$dir" 2>/dev/null || true
    else
        # Create if missing (especially unidentified which ARM expects)
        mkdir -p "$dir" 2>/dev/null || true
        chown "$ARM_UID:$ARM_GID" "$dir" 2>/dev/null || true
    fi
done

# Auto-cleanup failed jobs from database before starting
# This allows re-ripping discs that previously failed
echo "[arm-wrapper] Cleaning up any failed job entries..."
python3 -c "
import sqlite3
import os
import shutil

try:
    conn = sqlite3.connect('/home/arm/db/arm.db')
    cur = conn.cursor()

    # Get titles of failed jobs before deleting (to clean up their directories)
    cur.execute(\"SELECT DISTINCT title FROM job WHERE status = 'fail'\")
    failed_titles = [row[0] for row in cur.fetchall()]

    # Delete failed jobs
    cur.execute(\"DELETE FROM job WHERE status = 'fail'\")
    if cur.rowcount > 0:
        print(f'[arm-wrapper] Removed {cur.rowcount} failed job(s) from database')
    conn.commit()
    conn.close()

    # Clean up empty/partial directories from failed rips
    unid_path = '/home/arm/movies/unidentified'
    if os.path.exists(unid_path):
        for item in os.listdir(unid_path):
            item_path = os.path.join(unid_path, item)
            if os.path.isdir(item_path):
                # Remove empty directories or directories with only empty subdirs
                try:
                    contents = os.listdir(item_path)
                    # If empty or only contains empty 'extras' folder
                    if not contents or (contents == ['extras'] and not os.listdir(os.path.join(item_path, 'extras'))):
                        shutil.rmtree(item_path)
                        print(f'[arm-wrapper] Removed empty directory: {item}')
                except:
                    pass
except Exception as e:
    print(f'[arm-wrapper] DB cleanup skipped: {e}')
" 2>/dev/null || true

echo "[arm-wrapper] Launching ripper as arm user (UID: $ARM_UID)"

# Use gosu to drop privileges and run the ripper as the arm user
# This is the key fix - upstream runs this as root
exec /usr/sbin/gosu arm /usr/bin/python3 /opt/arm/arm/ripper/main.py -d "${DEVNAME}" 2>&1 | logger -t ARM -s
