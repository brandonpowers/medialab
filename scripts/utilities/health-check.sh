#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo root from this script's location so it works whether
# Medialab is installed at /opt/medialab or cloned anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[*] Medialab Health Check"
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
  ["Homepage"]="http://localhost:3000"
  ["Jellyseerr"]="http://localhost:5055"
  ["ARM"]="http://localhost:8090"
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

# Check external DNS resolution from inside a container. This surfaces the
# Docker embedded-resolver timeout (EAI_AGAIN) that otherwise fails silently -
# e.g. Radarr/Jellyseerr unable to reach api.themoviedb.org. See DOCKER_DNS in
# .env and the dns: pinning in docker-compose.yml.
echo "Checking external DNS resolution..."
dns_probe_host="api.themoviedb.org"
dns_probe_svc=""
for candidate in radarr sonarr prowlarr; do
  if docker compose ps --status running --services 2>/dev/null | grep -qx "$candidate"; then
    dns_probe_svc="$candidate"
    break
  fi
done

if [ -z "$dns_probe_svc" ]; then
  echo "  [-] Skipped - no probe container (radarr/sonarr/prowlarr) is running"
elif docker compose exec -T "$dns_probe_svc" getent hosts "$dns_probe_host" >/dev/null 2>&1; then
  echo "  [✓] External DNS resolution works ($dns_probe_host from $dns_probe_svc)"
else
  echo "  [✗] External DNS resolution FAILED for $dns_probe_host inside $dns_probe_svc"
  echo "      Docker's resolver may be timing out (EAI_AGAIN). Check DOCKER_DNS in .env"
  echo "      and the dns: pinning in docker-compose.yml."
  all_healthy=false
fi

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
