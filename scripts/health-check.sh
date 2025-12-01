#!/usr/bin/env bash
set -euo pipefail

cd /opt/homelab

echo "[*] Homelab Health Check"
echo "========================"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
  echo "[✗] Docker is not running"
  exit 1
fi

echo "[✓] Docker is running"
echo ""

# Check critical services
declare -A services=(
  ["Jellyfin"]="http://localhost:8096/health"
  ["Sonarr"]="http://localhost:8989/ping"
  ["Radarr"]="http://localhost:7878/ping"
  ["Lidarr"]="http://localhost:8686/ping"
  ["Prowlarr"]="http://localhost:9696/ping"
  ["Homarr"]="http://localhost:7575"
  ["Jellyseerr"]="http://localhost:5055"
)

all_healthy=true

echo "Checking services..."
for service in "${!services[@]}"; do
  url="${services[$service]}"
  if curl -sf "$url" >/dev/null 2>&1; then
    echo "  [✓] $service is healthy"
  else
    echo "  [✗] $service is down or not responding"
    all_healthy=false
  fi
done

echo ""

# Check container status
echo "Docker container status:"
docker compose ps

echo ""

if $all_healthy; then
  echo "[✓] All critical services are healthy"
  exit 0
else
  echo "[!] Some services are unhealthy - check logs with: docker compose logs servicename"
  exit 1
fi
