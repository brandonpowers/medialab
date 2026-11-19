#!/usr/bin/env bash
#
# update.sh - Pull the latest service images and recreate containers.
# Takes a configuration snapshot first so a bad image can be rolled back.
#
# Usage:
#   ./scripts/utilities/update.sh [--no-backup]
#
#   --no-backup   Skip the pre-update config snapshot (not recommended).
#
set -euo pipefail

# Resolve the repo root from this script's location so the tool works whether
# Medialab is installed at /opt/medialab or cloned anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/migrate.sh"

DO_BACKUP=true
for arg in "$@"; do
    case "$arg" in
        --no-backup) DO_BACKUP=false ;;
    esac
done

cd "$REPO_ROOT"

echo "[*] Medialab Update Script"
echo "========================="
echo ""

# Snapshot current config before changing anything, so a bad :latest image can
# be recovered (compose pulls floating tags, so updates are not reproducible).
if $DO_BACKUP; then
    echo "[1/6] Backing up configuration before update..."
    if "$SCRIPT_DIR/backup.sh"; then
        echo ""
    else
        echo "[!] Backup failed — aborting update. Use --no-backup to override."
        exit 1
    fi
else
    echo "[1/6] Skipping pre-update backup (--no-backup)."
    echo ""
fi

echo "[2/6] Pulling latest Docker images..."
docker compose pull

# Bring on-disk config in line with the current docker-compose.yml before the
# containers are recreated against it. Each step is idempotent (a no-op once
# applied), so this is safe on every run.
echo ""
echo "[3/6] Applying config migrations..."
arm_config="$REPO_ROOT/data/arm/config/arm.yaml"
if [[ -f "$arm_config" ]]; then
    while IFS= read -r key; do
        echo "    ARM: $key moved to the single-mount layout"
    done < <(arm_migrate_media_paths "$arm_config")
fi
if ! ensure_seerr_config_owner "$REPO_ROOT/data/jellyseerr/config"; then
    echo "[!] Seerr needs data/jellyseerr/config owned by ${SEERR_UID}:${SEERR_GID} and this"
    echo "    run could not change it. Fix with:"
    echo "        sudo chown -R ${SEERR_UID}:${SEERR_GID} $REPO_ROOT/data/jellyseerr/config"
fi

echo ""
echo "[4/6] Recreating containers with new images..."
docker compose up -d

echo ""
echo "[5/6] Cleaning up old images..."
docker image prune -f

echo ""
echo "[6/6] Verifying service health..."
# Give containers a moment to start before probing.
sleep 10
if "$SCRIPT_DIR/health-check.sh"; then
    echo ""
    echo "[✓] Update complete — all checked services are healthy."
else
    echo ""
    echo "[!] Update applied, but some services are not healthy yet."
    echo "    They may still be starting. Re-check with:"
    echo "        $SCRIPT_DIR/health-check.sh"
    echo "    Inspect logs with: docker compose logs -f <servicename>"
    echo "    If an updated image is broken, restore the pre-update snapshot:"
    echo "        $SCRIPT_DIR/restore.sh <latest backup>"
fi
