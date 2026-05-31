#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo root from this script's location so it works whether
# Medialab is installed at /opt/medialab or cloned anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[*] Environment Configuration Validator"
echo "========================================"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
  echo "[✗] Error: .env file not found"
  echo "    Create it from: cp .env.example .env"
  exit 1
fi

echo "[✓] .env file exists"
echo ""

# Required variables
required_vars=(
  "TZ"
  "PUID"
  "PGID"
  "MEDIA_ROOT"
  "CLOUDFLARE_TUNNEL_TOKEN"
  "TMDB_API_KEY"
)

missing=()
unconfigured=()

echo "Checking required variables..."

for var in "${required_vars[@]}"; do
  # Check if variable exists
  if ! grep -q "^${var}=" .env 2>/dev/null; then
    missing+=("$var")
    echo "  [✗] $var - MISSING"
  # Check if it's still set to placeholder value
  elif grep -q "^${var}=.*_here$" .env 2>/dev/null; then
    unconfigured+=("$var")
    echo "  [!] $var - NEEDS CONFIGURATION (still set to placeholder)"
  else
    echo "  [✓] $var - configured"
  fi
done

echo ""

# Check optional but recommended variables
optional_vars=(
  "SONARR_API_KEY"
  "RADARR_API_KEY"
)

echo "Checking optional variables (for Recyclarr)..."
for var in "${optional_vars[@]}"; do
  if grep -q "^${var}=.*_here$" .env 2>/dev/null || ! grep -q "^${var}=" .env 2>/dev/null; then
    echo "  [!] $var - not configured (optional, needed for Recyclarr)"
  else
    echo "  [✓] $var - configured"
  fi
done

echo ""
echo "================================"

# Final report
if [ ${#missing[@]} -gt 0 ]; then
  echo "[✗] VALIDATION FAILED - Missing variables:"
  printf '    - %s\n' "${missing[@]}"
  echo ""
  exit 1
elif [ ${#unconfigured[@]} -gt 0 ]; then
  echo "[!] VALIDATION WARNING - Unconfigured variables:"
  printf '    - %s\n' "${unconfigured[@]}"
  echo ""
  echo "Edit .env and replace placeholder values with actual credentials"
  exit 1
else
  echo "[✓] VALIDATION PASSED"
  echo ""
  echo "All required variables are configured!"
  echo "Ready to start: docker compose up -d"
  exit 0
fi
