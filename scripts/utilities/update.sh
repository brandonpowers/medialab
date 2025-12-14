#!/usr/bin/env bash
set -euo pipefail

cd /opt/homelab

echo "[*] Homelab Update Script"
echo "========================="
echo ""

echo "[1/4] Pulling latest Docker images..."
docker compose pull

echo ""
echo "[2/4] Recreating containers with new images..."
docker compose up -d

echo ""
echo "[3/4] Cleaning up old images..."
docker image prune -f

echo ""
echo "[4/4] Checking service status..."
docker compose ps

echo ""
echo "[✓] Update complete!"
echo ""
echo "Services updated and running."
echo "Check logs if needed: docker compose logs -f servicename"
