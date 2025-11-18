#!/usr/bin/env bash
set -euo pipefail

# -------- Config (override via env) --------
CTID="${CTID:-101}"
HOSTNAME="${HOSTNAME:-docker-host}"
BRIDGE="${BRIDGE:-vmbr0}"
TEMPLATE="${TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

CORES="${CORES:-8}"
MEMORY_MB="${MEMORY_MB:-24576}"
SWAP_MB="${SWAP_MB:-1024}"
DISK_SIZE="${DISK_SIZE:-100G}"

HOST_MEDIA_PATH="${HOST_MEDIA_PATH:-/mnt/media}"

# Optional: set a password non-interactively by exporting CT_PASSWORD
CT_PASSWORD="${CT_PASSWORD:-}"

# -------- Helpers --------
already_has_line() { grep -qxF "$1" "$2"; }
append_once() { local line="$1" file="$2"; already_has_line "$line" "$file" || echo "$line" >> "$file"; }
ct_exists() { pct status "$CTID" &>/dev/null; }
ct_running() { [[ "$(pct status "$CTID" 2>/dev/null || true)" == *"status: running"* ]]; }

changed=false

# -------- Ensure template exists --------
TEMPLATE_BASENAME=$(basename "$TEMPLATE")
if [[ "$TEMPLATE" == local:* ]]; then
  if ! pveam list local 2>/dev/null | grep -q "$TEMPLATE_BASENAME"; then
    echo "[!] Template $TEMPLATE_BASENAME not found in local storage."
    echo "    Download it with:"
    echo "    pveam update && pveam download local $TEMPLATE_BASENAME"
    exit 1
  fi
fi

# -------- Create CT if needed --------
if ! ct_exists; then
  echo "[*] Creating CT $CTID ($HOSTNAME)"
  if [[ -n "$CT_PASSWORD" ]]; then
    pct create "$CTID" "$TEMPLATE" \
      --hostname "$HOSTNAME" \
      --password "$CT_PASSWORD" \
      --unprivileged 1 \
      --cores "$CORES" --memory "$MEMORY_MB" --swap "$SWAP_MB" \
      --rootfs "local-lvm:20" \
      --features nesting=1,keyctl=1,fuse=1 \
      --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
      --cmode shell --ostype ubuntu
  else
    pct create "$CTID" "$TEMPLATE" \
      --hostname "$HOSTNAME" \
      --unprivileged 1 \
      --cores "$CORES" --memory "$MEMORY_MB" --swap "$SWAP_MB" \
      --rootfs "local-lvm:20" \
      --features nesting=1,keyctl=1,fuse=1 \
      --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
      --cmode shell --ostype ubuntu \
      --password
  fi
  changed=true
else
  echo "[*] CT $CTID already exists; ensuring settings."
  pct set "$CTID" -cores "$CORES" || true
  pct set "$CTID" -memory "$MEMORY_MB" -swap "$SWAP_MB" || true
fi

# -------- Resize disk --------
if pct resize "$CTID" rootfs "$DISK_SIZE"; then
  changed=true
fi

# -------- Ensure host media dir --------
mkdir -p "$HOST_MEDIA_PATH"

# Create all required media subdirectories
mkdir -p "$HOST_MEDIA_PATH"/{movies,tv,music,audiobooks,books,podcasts,downloads/{complete,incomplete},photos}

# Set proper ownership (1000:1000 is typical for unprivileged containers)
chown -R 1000:1000 "$HOST_MEDIA_PATH" 2>/dev/null || true
chmod -R 775 "$HOST_MEDIA_PATH" 2>/dev/null || true

# -------- Update CT config (idempotent) --------
CONF="/etc/pve/lxc/${CTID}.conf"
touch "$CONF"

append_once "mp0: ${HOST_MEDIA_PATH},mp=/mnt/media" "$CONF"
append_once "lxc.cgroup2.devices.allow: c 226:* rwm" "$CONF"
append_once "lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir" "$CONF"

# -------- Host sysctl for inotify (applies to CT processes) --------
if ! grep -q "fs.inotify.max_user_watches=1048576" /etc/sysctl.conf 2>/dev/null; then
  echo "fs.inotify.max_user_watches=1048576" >> /etc/sysctl.conf
  echo "fs.inotify.max_user_instances=1024"  >> /etc/sysctl.conf
  sysctl --system || true
fi

# -------- Start/restart CT if needed --------
if ct_running; then
  if [[ "$changed" == true ]]; then
    echo "[*] Restarting CT $CTID to apply changes"
    pct restart "$CTID"
  else
    echo "[*] CT $CTID already running; no restart needed."
  fi
else
  echo "[*] Starting CT $CTID"
  pct start "$CTID"
fi

# -------- Copy homelab files into container --------
echo "[*] Copying homelab files to container..."

# Determine the script's parent directory (homelab root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_ROOT="$(dirname "$SCRIPT_DIR")"

# Create /opt/homelab in container if it doesn't exist
pct exec "$CTID" -- mkdir -p /opt/homelab

# Use pct push to copy files (works for both privileged and unprivileged containers)
echo "[*] Copying files from $HOMELAB_ROOT to CT:/opt/homelab"

# Create a temporary tarball
TEMP_TAR="/tmp/homelab-$CTID.tar.gz"
tar -czf "$TEMP_TAR" \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='data' \
  --exclude='*.backup.*' \
  --exclude='.passwords.txt' \
  -C "$HOMELAB_ROOT" .

# Push tarball to container and extract
pct push "$CTID" "$TEMP_TAR" /tmp/homelab.tar.gz
pct exec "$CTID" -- tar -xzf /tmp/homelab.tar.gz -C /opt/homelab
pct exec "$CTID" -- rm /tmp/homelab.tar.gz
rm "$TEMP_TAR"

# Make scripts executable
pct exec "$CTID" -- chmod +x /opt/homelab/ct/install-service.sh
pct exec "$CTID" -- chmod +x /opt/homelab/scripts/*.sh 2>/dev/null || true

echo "[✓] Files copied to container"
echo "[✓] Done. Enter CT with: pct enter $CTID"
echo ""
echo "Next steps:"
echo "  1. pct enter $CTID"
echo "  2. cd /opt/homelab"
echo "  3. ./scripts/setup-homelab.sh    # Automated setup with password generation"
echo "  4. ./ct/install-service.sh       # Optional: Enable auto-start on boot"
