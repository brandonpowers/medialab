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
for dir in /home/arm/media/raw /home/arm/media/transcode /home/arm/media/completed; do
    if [[ -d "$dir" ]]; then
        chown "$ARM_UID:$ARM_GID" "$dir" 2>/dev/null || true
    fi
done

echo "[arm-wrapper] Launching ripper as arm user (UID: $ARM_UID)"

# Use gosu to drop privileges and run the ripper as the arm user
# This is the key fix - upstream runs this as root
exec /usr/sbin/gosu arm /usr/bin/python3 /opt/arm/arm/ripper/main.py -d "${DEVNAME}" 2>&1 | logger -t ARM -s
