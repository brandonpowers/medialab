#!/usr/bin/env bash
#
# update.sh - Pull the latest service images and recreate containers.
# Takes a configuration snapshot first so a bad image can be rolled back.
#
# Order: pull (no downtime) → stop → snapshot → migrate config → recreate.
# The stack is stopped only for the snapshot so databases are captured at rest
# (a hot copy of a live SQLite DB can be inconsistent). If anything fails while
# it is stopped, the existing containers are started again on exit.
#
# Usage:
#   ./scripts/utilities/update.sh [--no-backup]
#
#   --no-backup   Skip the pre-update config snapshot and the stop it needs
#                 (not recommended).
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

# Pull first: it can take a while and needs no downtime. A failed pull exits
# here with the stack untouched.
echo "[1/6] Pulling latest Docker images..."
docker compose pull

# If we exit while the stack is stopped (failed backup, any error under set -e),
# start the existing containers again rather than leaving services down.
# `start` restarts the stopped containers as-is; it does not recreate them on
# the newly pulled images.
STACK_STOPPED=false
restart_if_stopped() {
    if $STACK_STOPPED; then
        echo "[!] Update did not complete — starting the existing containers again..."
        docker compose start || true
    fi
}
trap restart_if_stopped EXIT

# Snapshot config before changing anything, so a bad :latest image can be
# recovered (compose pulls floating tags, so updates are not reproducible).
echo ""
if $DO_BACKUP; then
    echo "[2/6] Stopping services and backing up configuration..."
    STACK_STOPPED=true
    docker compose stop
    if ! "$SCRIPT_DIR/backup.sh"; then
        echo "[!] Backup failed — aborting update. Use --no-backup to override."
        exit 1
    fi
else
    echo "[2/6] Skipping pre-update backup (--no-backup)."
fi

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
homepage_services="$REPO_ROOT/data/homepage/config/services.yaml"
if [[ -f "$homepage_services" ]]; then
    while IFS= read -r change; do
        echo "    Homepage: added widget field $change"
    done < <(homepage_migrate_services "$homepage_services")
fi
recyclarr_config="$REPO_ROOT/data/recyclarr/config/recyclarr.yml"
if [[ -f "$recyclarr_config" ]]; then
    while IFS= read -r change; do
        echo "    Recyclarr: $change"
    done < <(recyclarr_migrate_config "$recyclarr_config")
fi
if ! ensure_seerr_config_owner "$REPO_ROOT/data/jellyseerr/config"; then
    echo "[!] Seerr needs data/jellyseerr/config owned by ${SEERR_UID}:${SEERR_GID} and this"
    echo "    run could not change it. Fix with:"
    echo "        sudo chown -R ${SEERR_UID}:${SEERR_GID} $REPO_ROOT/data/jellyseerr/config"
fi

echo ""
echo "[4/6] Recreating containers with new images..."
docker compose up -d
STACK_STOPPED=false

echo ""
echo "[5/6] Cleaning up old images..."
docker image prune -f

echo ""
echo "[6/6] Verifying service health..."
# A major version can run long migrations on first start (Jellyfin 10.11 → 12
# serves a placeholder for minutes), so poll for up to HEALTH_WAIT seconds
# instead of judging after one fixed pause. Only the final attempt's report is
# shown.
HEALTH_WAIT="${HEALTH_WAIT:-300}"
healthy=false
waited=0
while (( waited < HEALTH_WAIT )); do
    sleep 15
    waited=$((waited + 15))
    if "$SCRIPT_DIR/health-check.sh" > /dev/null 2>&1; then
        healthy=true
        break
    fi
    echo "    still starting... (${waited}s)"
done
if $healthy; then
    "$SCRIPT_DIR/health-check.sh" || true
    echo ""
    echo "[✓] Update complete — all checked services are healthy."
else
    "$SCRIPT_DIR/health-check.sh" || true
    echo ""
    echo "[!] Update applied, but some services are not healthy after ${HEALTH_WAIT}s."
    echo "    They may still be starting. Re-check with:"
    echo "        $SCRIPT_DIR/health-check.sh"
    echo "    Inspect logs with: docker compose logs -f <servicename>"
    echo "    If an updated image is broken, restore the pre-update snapshot:"
    echo "        $SCRIPT_DIR/restore.sh <latest backup>"
fi
