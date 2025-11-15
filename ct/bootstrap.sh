#!/usr/bin/env bash
set -euo pipefail

echo "[*] Homelab Bootstrap Script"
echo "================================"

# Pre-flight checks
echo "[*] Running pre-flight checks..."

# Check available disk space (need at least 20GB)
available_kb=$(df /opt | awk 'NR==2 {print $4}')
available_gb=$((available_kb / 1024 / 1024))
if [ "$available_gb" -lt 20 ]; then
  echo "[!] WARNING: Less than 20GB available in /opt (${available_gb}GB free)"
  echo "    Recommend at least 20GB for Docker images and data"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Check for GPU (optional, just warn if missing)
if [ ! -d /dev/dri ]; then
  echo "[!] WARNING: /dev/dri not found - hardware transcoding unavailable"
  echo "    This is OK if you're not using Intel GPU transcoding"
fi

# Detect and install Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "[*] Docker not found, installing..."
  apt update && apt install -y ca-certificates curl gnupg lsb-release git nano uidmap

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Verify Docker installation
  if ! command -v docker >/dev/null 2>&1; then
    echo "[!] ERROR: Docker installation failed"
    exit 1
  fi

  systemctl enable --now docker
  echo "[✓] Docker installed successfully."
else
  echo "[✓] Docker already installed."
fi

# Verify Docker Compose
if docker compose version &>/dev/null; then
  echo "[✓] Docker Compose plugin found."
else
  echo "[!] ERROR: Docker Compose plugin not found"
  exit 1
fi

# Ensure repo location
mkdir -p /opt/homelab
if [ ! -f /opt/homelab/docker-compose.yml ]; then
  echo "[!] /opt/homelab/docker-compose.yml not found."
  echo "    Place your repo at /opt/homelab (e.g., git clone ...) then re-run this script."
  exit 1
fi

cd /opt/homelab

# Create ALL service directories
echo "[*] Creating service data directories..."
mkdir -p data/{cloudflared,tailscale,homarr/{configs,icons},jellyfin/{config,cache},jellyseerr/config}
mkdir -p data/{audiobookshelf/{config,metadata},calibre-web/config}
mkdir -p data/{sonarr/config,radarr/config,lidarr/config,readarr/config,prowlarr/config,bazarr/config}
mkdir -p data/{recyclarr/config,qbittorrent/config,sabnzbd/config}
mkdir -p data/{tdarr/{server,configs,logs}}
mkdir -p data/{immich/model-cache}
echo "[✓] Service directories created."

# Ensure .env exists (create from example if missing)
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    echo "[*] Created .env from .env.example"
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║ IMPORTANT: Edit .env file with your actual credentials!   ║"
    echo "║                                                            ║"
    echo "║ Required before starting:                                 ║"
    echo "║   - DB_PASSWORD (openssl rand -base64 32)                 ║"
    echo "║   - REDIS_PASSWORD (openssl rand -base64 32)              ║"
    echo "║   - CLOUDFLARE_TUNNEL_TOKEN                               ║"
    echo "║   - TAILSCALE_AUTH_KEY                                    ║"
    echo "║   - TMDB_API_KEY                                          ║"
    echo "║   - Verify TZ, PUID, PGID                                 ║"
    echo "║                                                            ║"
    echo "║ Command: nano .env                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
  else
    echo "[!] ERROR: .env.example not found, cannot create .env"
    exit 1
  fi
else
  echo "[✓] .env file already exists."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ Bootstrap complete!                                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Edit .env with your credentials: nano .env"
echo "  2. Validate configuration: bash scripts/validate-env.sh"
echo "  3. Pull Docker images: docker compose pull"
echo "  4. Start the stack: docker compose up -d"
echo "  5. Check status: docker compose ps"
echo ""
echo "To enable auto-start on boot:"
echo "  cd /opt/homelab/ct"
echo "  ./install-service.sh"
echo ""
