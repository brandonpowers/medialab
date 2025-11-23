#!/bin/bash
set -e

# Homelab Automated Setup Script
# This script automates the complete setup of your homelab infrastructure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   HOMELAB AUTOMATED SETUP                                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

generate_password() {
    openssl rand -base64 32
}

# Check if running in correct directory
check_directory() {
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found!"
        print_error "Please run this script from the homelab directory"
        exit 1
    fi
    print_success "Running in correct directory"
}

# Install Docker
install_docker() {
    print_info "Installing Docker (official method)..."

    # Update package index
    apt-get update -qq

    # Install prerequisites
    apt-get install -y ca-certificates curl &>/dev/null
    install -m 0755 -d /etc/apt/keyrings

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update -qq
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null; then
        print_success "Docker installed successfully"

        # Start and enable Docker
        systemctl start docker
        systemctl enable docker &>/dev/null

        print_success "Docker service started"

        # Configure Docker daemon
        configure_docker_daemon
    else
        print_error "Failed to install Docker"
        exit 1
    fi
}

# Configure Docker daemon settings
configure_docker_daemon() {
    print_info "Configuring Docker daemon..."
    mkdir -p /etc/docker

    # Check if daemon.json exists
    if [ -f /etc/docker/daemon.json ]; then
        print_info "Backing up existing daemon.json..."
        cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
    fi

    # Create daemon.json with IPv6 disabled and log rotation
    cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
  "ipv6": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKEREOF

    # Configure Docker for LXC environment (disables AppArmor integration)
    print_info "Configuring Docker systemd service for LXC environment..."
    mkdir -p /etc/systemd/system/docker.service.d

    cat > /etc/systemd/system/docker.service.d/lxc-environment.conf <<'SYSTEMDEOF'
[Service]
Environment="container=lxc"
SYSTEMDEOF

    # Reload systemd and restart Docker to apply changes
    systemctl daemon-reload
    systemctl restart docker
    print_success "Docker daemon configured and restarted"
}

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Check Docker
    if command -v docker &> /dev/null; then
        print_success "Docker installed: $(docker --version)"

        # Configure Docker daemon even if already installed
        configure_docker_daemon
    else
        print_warning "Docker not found - installing..."
        install_docker
    fi

    # Check Docker Compose (will be installed with Docker)
    if command -v docker compose &> /dev/null; then
        print_success "Docker Compose installed: $(docker compose version)"
    else
        print_error "Docker Compose not found after Docker installation"
        exit 1
    fi

    # Check openssl
    if command -v openssl &> /dev/null; then
        print_success "OpenSSL installed"
    else
        print_error "OpenSSL not found - needed for password generation"
        print_info "Installing openssl..."
        if apt-get install -y openssl &>/dev/null; then
            print_success "OpenSSL installed"
        else
            print_error "Failed to install openssl"
            exit 1
        fi
    fi
}

# Backup existing .env if it exists
backup_env() {
    if [ -f .env ]; then
        local backup_file=".env.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "Existing .env found - backing up to $backup_file"
        cp .env "$backup_file"
        print_success "Backup created"
    fi
}

# Generate .env file
generate_env() {
    print_section "Generating Environment Configuration"

    # Check if .env exists and ask user
    if [ -f .env ]; then
        echo -n "⚠ .env already exists. Overwrite? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping .env generation"
            return
        fi
        backup_env
    fi

    print_info "Generating secure passwords and tokens..."

    # Generate all passwords and tokens
    local DB_PASSWORD=$(generate_password)
    local REDIS_PASSWORD=$(generate_password)
    local HOMARR_ENCRYPTION_KEY=$(openssl rand -hex 32)

    print_success "Generated database password"
    print_success "Generated Redis password"
    print_success "Generated Homarr encryption key"

    # Prompt for required values
    print_info "\nPlease provide the following information:"

    echo -n "Timezone (default: America/Chicago): "
    read -r TZ
    TZ=${TZ:-America/Chicago}

    echo -n "PUID (default: 1000): "
    read -r PUID
    PUID=${PUID:-1000}

    echo -n "PGID (default: 1000): "
    read -r PGID
    PGID=${PGID:-1000}

    echo -n "Media root path (default: /mnt/media): "
    read -r MEDIA_ROOT
    MEDIA_ROOT=${MEDIA_ROOT:-/mnt/media}

    echo -n "Domain name (default: glaance.io): "
    read -r DOMAIN
    DOMAIN=${DOMAIN:-glaance.io}

    echo -n "Your email: "
    read -r EMAIL

    echo -n "Cloudflare Tunnel Token (press Enter to skip for now): "
    read -r CLOUDFLARE_TUNNEL_TOKEN
    CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-your_tunnel_token_here}

    echo -n "Tailscale Auth Key (press Enter to skip for now): "
    read -r TAILSCALE_AUTH_KEY
    TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY:-tskey-auth-xxxxxxxxxxxxx}

    echo -n "TMDB API Key (press Enter to skip for now): "
    read -r TMDB_API_KEY
    TMDB_API_KEY=${TMDB_API_KEY:-your_tmdb_api_key_here}

    # Create .env file
    cat > .env << EOF
# ============================================
# HOMELAB ENVIRONMENT CONFIGURATION
# Generated: $(date)
# ============================================

# System Configuration
TZ=${TZ}
PUID=${PUID}
PGID=${PGID}
MEDIA_ROOT=${MEDIA_ROOT}

# Domain Configuration
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}

# Remote Access
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}

# Database & Cache (Auto-generated)
DB_USER=homelab
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Homarr v1.0 (Auto-generated)
HOMARR_ENCRYPTION_KEY=${HOMARR_ENCRYPTION_KEY}

# API Keys
TMDB_API_KEY=${TMDB_API_KEY}

# Recyclarr API Keys (configure after services are running)
SONARR_API_KEY=your_sonarr_api_key_here
RADARR_API_KEY=your_radarr_api_key_here
EOF

    print_success ".env file created successfully"

    # Save passwords to a secure file for reference
    cat > .passwords.txt << EOF
HOMELAB PASSWORDS - $(date)
KEEP THIS FILE SECURE!

Database Password: ${DB_PASSWORD}
Redis Password: ${REDIS_PASSWORD}
Homarr Encryption Key: ${HOMARR_ENCRYPTION_KEY}

These passwords have been added to .env
Consider storing them in a password manager and deleting this file.
EOF
    chmod 600 .passwords.txt

    print_success "Passwords saved to .passwords.txt (chmod 600)"
    print_warning "Store these passwords securely and delete .passwords.txt when done"
}

# Create data directories
create_directories() {
    print_section "Creating Data Directories"

    local dirs=(
        "data/homarr/configs"
        "data/homarr/icons"
        "data/jellyfin/config"
        "data/jellyfin/cache"
        "data/jellyseerr/config"
        "data/audiobookshelf/config"
        "data/audiobookshelf/metadata"
        "data/calibre-web/config"
        "data/sonarr/config"
        "data/radarr/config"
        "data/lidarr/config"
        "data/prowlarr/config"
        "data/bazarr/config"
        "data/recyclarr/config"
        "data/qbittorrent/config"
        "data/sabnzbd/config"
        "data/tdarr/server"
        "data/tdarr/configs"
        "data/tdarr/logs"
        "data/arm/config"
        "data/arm/db"
        "data/arm/logs"
        "data/arm/media"
        "data/immich"
        "data/tailscale"
        "data/ovos/config/phal"
        "data/ovos/share"
        "data/ovos/tmp"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_success "Created $dir"
        else
            print_info "Already exists: $dir"
        fi
    done

    # Fix ownership for ARM directories (requires PUID:PGID)
    if [ -d "data/arm" ]; then
        print_info "Setting ownership for ARM directories..."
        chown -R ${PUID}:${PGID} data/arm
        print_success "ARM directory ownership set to ${PUID}:${PGID}"
    fi

    print_success "All data directories ready"
}

# Setup Open Voice OS configuration
setup_ovos() {
    print_section "Setting Up Open Voice OS"

    # Create OVOS config file if it doesn't exist
    if [ ! -f "data/ovos/config/mycroft.conf" ]; then
        print_info "Creating OVOS configuration file..."
        cat > data/ovos/config/mycroft.conf << 'EOFCONF'
{
  "lang": "en-us",
  "logs": {
    "path": "stdout"
  },
  "play_wav_cmdline": "paplay %1",
  "listener": {
    "wake_word": "hey_mycroft",
    "stand_up_word": "wake_up",
    "phoneme_duration": 120,
    "multiplier": 1.0,
    "energy_ratio": 1.5,
    "recording_timeout": 10.0,
    "recording_timeout_with_silence": 3.0
  },
  "stt": {
    "module": "ovos-stt-plugin-vosk"
  },
  "tts": {
    "module": "ovos-tts-plugin-mimic3"
  },
  "gui": {
    "enabled": true,
    "idle_display_skill": "skill-ovos-homescreen.openvoiceos"
  },
  "skills": {
    "blacklisted_skills": [],
    "priority_skills": []
  },
  "server": {
    "disabled": true
  },
  "enclosure": {
    "platform": "generic"
  }
}
EOFCONF
        print_success "OVOS configuration created"
    else
        print_info "OVOS configuration already exists"
    fi

    # Check for audio device access
    print_info "Checking audio device availability..."
    if [ -e /dev/snd ]; then
        print_success "Audio devices found at /dev/snd"
    else
        print_warning "Audio devices not found at /dev/snd"
        print_warning "OVOS audio services may not work without audio device passthrough"
        print_info "On Proxmox host, run: pct set <CTID> -dev0 /dev/snd,/dev/snd"
    fi

    # Check if user is in audio group (idempotent)
    local CURRENT_USER=$(whoami)
    if groups "$CURRENT_USER" | grep -q '\baudio\b'; then
        print_info "User already in audio group"
    else
        print_info "Adding user to audio group..."
        if sudo usermod -aG audio "$CURRENT_USER" 2>/dev/null; then
            print_success "User added to audio group (requires re-login to take effect)"
        else
            print_warning "Could not add user to audio group (may require manual configuration)"
        fi
    fi

    # Check for PulseAudio
    print_info "Checking audio system..."
    if [ -S "/run/user/1000/pulse/native" ]; then
        print_success "PulseAudio socket found"
    elif command -v pulseaudio &> /dev/null; then
        print_info "PulseAudio installed but socket not found"
        print_info "Starting PulseAudio..."
        pulseaudio --start 2>/dev/null || true
    else
        print_warning "PulseAudio not found - installing..."
        if sudo apt-get update && sudo apt-get install -y pulseaudio pulseaudio-utils 2>/dev/null; then
            print_success "PulseAudio installed"
            pulseaudio --start 2>/dev/null || true
        else
            print_warning "Could not install PulseAudio automatically"
        fi
    fi

    # Enable user lingering (idempotent)
    if loginctl show-user "$CURRENT_USER" 2>/dev/null | grep -q "Linger=yes"; then
        print_info "User lingering already enabled"
    else
        print_info "Enabling user lingering..."
        if sudo loginctl enable-linger "$CURRENT_USER" 2>/dev/null; then
            print_success "User lingering enabled"
        else
            print_warning "Could not enable user lingering (may require manual configuration)"
        fi
    fi
}

# Validate docker-compose.yml
validate_compose() {
    print_section "Validating Docker Compose Configuration"

    if docker compose config --quiet 2>&1 | grep -q "error"; then
        print_error "docker-compose.yml validation failed"
        docker compose config
        exit 1
    else
        print_success "docker-compose.yml is valid"
    fi
}

# Pull Docker images
pull_images() {
    print_section "Pulling Docker Images"

    print_info "This may take several minutes depending on your internet connection..."

    if docker compose pull; then
        print_success "All images pulled successfully"
    else
        print_warning "Some images may have failed to pull - check output above"
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Start services
start_services() {
    print_section "Starting Services"

    print_info "Starting all services in detached mode..."

    if docker compose up -d; then
        print_success "All services started"
    else
        print_error "Failed to start services"
        exit 1
    fi
}

# Wait for services to be healthy
wait_for_services() {
    print_section "Waiting for Services to be Healthy"

    print_info "Waiting for postgres..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker exec postgres pg_isready -U homelab &> /dev/null; then
            print_success "PostgreSQL is healthy"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_warning "PostgreSQL health check timed out (may still be starting)"
    fi

    print_info "Waiting for redis..."
    attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker exec redis redis-cli --raw incr ping &> /dev/null; then
            print_success "Redis is healthy"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_warning "Redis health check timed out (may still be starting)"
    fi

    echo ""
    print_success "Core services are ready"
}

# Verify databases were created
verify_databases() {
    print_section "Verifying Databases"

    print_info "Checking PostgreSQL databases..."

    local databases=("immich" "uptimekuma")

    for db in "${databases[@]}"; do
        if docker exec postgres psql -U homelab -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$db"; then
            print_success "Database '$db' exists"
        else
            print_warning "Database '$db' not found (may still be initializing)"
        fi
    done
}

# Show service status
show_status() {
    print_section "Service Status"

    docker compose ps
}

# Show access information
show_access_info() {
    print_section "Access Information"

    echo -e "${GREEN}Public Services (via Cloudflare Tunnel):${NC}"
    echo "  Homarr:         https://homarr.${DOMAIN:-glaance.io}"
    echo "  Jellyfin:       https://jellyfin.${DOMAIN:-glaance.io}"
    echo "  Jellyseerr:     https://jellyseerr.${DOMAIN:-glaance.io}"
    echo "  Immich:         https://photos.${DOMAIN:-glaance.io}"
    echo "  Audiobookshelf: https://audiobooks.${DOMAIN:-glaance.io}"
    echo "  Calibre-web:    https://books.${DOMAIN:-glaance.io}"

    echo -e "\n${BLUE}Admin Services (via Tailscale):${NC}"
    echo "  Gitea:          http://homelab-media:3000"
    echo "  Portainer:      https://homelab-media:9443"
    echo "  Sonarr:         http://homelab-media:8989"
    echo "  Radarr:         http://homelab-media:7878"
    echo "  Prowlarr:       http://homelab-media:9696"
    echo "  Uptime Kuma:    http://homelab-media:3001"
    echo "  OVOS GUI:       http://homelab-media:8484"
    echo "  (and more...)"

    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "  1. Configure Cloudflare Tunnel routes (see README.md)"
    echo "  2. Set up Tailscale (see README.md)"
    echo "  3. Configure media libraries in *arr apps"
    echo "  4. Configure ARM for Blu-ray ripping: http://192.168.8.202:8090"

    echo -e "\n${YELLOW}Important Files:${NC}"
    echo "  .passwords.txt - Auto-generated passwords (DELETE after storing securely)"
    echo "  .env           - Environment configuration"
    echo "  data/          - All service data"
}

# Main execution
main() {
    print_header

    check_directory
    check_prerequisites
    generate_env
    create_directories
    setup_ovos
    validate_compose
    pull_images
    start_services
    sleep 10  # Give services a moment to initialize
    wait_for_services
    verify_databases
    show_status
    show_access_info

    echo ""
    print_section "Setup Complete!"
    print_success "Your homelab is now running!"
    print_info "Check logs with: docker compose logs -f"
    print_info "Stop services with: docker compose down"
    print_info "Update services with: docker compose pull && docker compose up -d"

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Run main function
main
