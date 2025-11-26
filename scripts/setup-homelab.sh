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

# Display available drives and let user select one for media storage
select_media_drive() {
    print_section "Media Drive Selection"

    print_info "Scanning for available drives..."
    echo ""

    # Get list of block devices (excluding loop, ram, and partitions)
    # Show: NAME, SIZE, TYPE, MOUNTPOINT, MODEL
    local drives=()
    local drive_info=()
    local i=1

    # Read drives into array
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local type=$(echo "$line" | awk '{print $3}')
        local mountpoint=$(echo "$line" | awk '{print $4}')
        local model=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf $i" "; print ""}' | xargs)

        # Skip if it's the boot/root drive
        if [ "$mountpoint" == "/" ] || [ "$mountpoint" == "/boot" ] || [ "$mountpoint" == "/boot/efi" ]; then
            continue
        fi

        drives+=("$name")
        drive_info+=("$size|$type|$mountpoint|$model")
    done < <(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL -n | grep -E "^(sd|nvme|vd)" | grep -v "loop")

    if [ ${#drives[@]} -eq 0 ]; then
        print_warning "No additional drives found"
        print_info "Using default media path: /mnt/media"
        SELECTED_MEDIA_PATH="/mnt/media"
        return
    fi

    echo -e "${BLUE}Available drives:${NC}"
    echo ""
    printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "#" "DEVICE" "SIZE" "TYPE" "MOUNTPOINT" "MODEL"
    echo "  ─────────────────────────────────────────────────────────────────────────────"

    for idx in "${!drives[@]}"; do
        local name="${drives[$idx]}"
        IFS='|' read -r size type mountpoint model <<< "${drive_info[$idx]}"
        mountpoint=${mountpoint:-"(not mounted)"}
        model=${model:-"Unknown"}
        printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "[$((idx+1))]" "/dev/$name" "$size" "$type" "$mountpoint" "$model"
    done

    echo ""
    printf "  %-4s %-12s\n" "[S]" "Skip - use default path (/mnt/media)"
    echo ""

    # Get user selection
    while true; do
        echo -n "Select a drive for media storage (1-${#drives[@]} or S to skip): "
        read -r selection

        if [[ "$selection" =~ ^[Ss]$ ]]; then
            print_info "Using default media path: /mnt/media"
            SELECTED_MEDIA_PATH="/mnt/media"
            return
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#drives[@]}" ]; then
            local selected_drive="${drives[$((selection-1))]}"
            local selected_info="${drive_info[$((selection-1))]}"
            IFS='|' read -r size type mountpoint model <<< "$selected_info"

            echo ""
            print_info "Selected: /dev/$selected_drive ($size - $model)"

            setup_media_drive "/dev/$selected_drive" "$mountpoint"
            return
        fi

        print_error "Invalid selection. Please enter a number between 1 and ${#drives[@]}, or S to skip."
    done
}

# Setup the selected media drive (format if needed, mount)
setup_media_drive() {
    local device="$1"
    local current_mount="$2"
    local mount_point="/mnt/media"

    # Check if drive is already mounted
    if [ -n "$current_mount" ] && [ "$current_mount" != "(not mounted)" ]; then
        print_info "Drive is already mounted at: $current_mount"
        echo -n "Use existing mount point '$current_mount'? (Y/n): "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            SELECTED_MEDIA_PATH="$current_mount"
            print_success "Using existing mount: $SELECTED_MEDIA_PATH"
            create_media_structure "$SELECTED_MEDIA_PATH"
            return
        fi
    fi

    # Check for existing partitions
    local partitions=$(lsblk -n -o NAME "$device" | tail -n +2)
    local partition_to_use=""

    if [ -n "$partitions" ]; then
        print_info "Drive has existing partitions:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL "$device"
        echo ""

        echo "Options:"
        echo "  [1] Use existing partition (select which one)"
        echo "  [2] Format entire drive (WARNING: ERASES ALL DATA)"
        echo "  [3] Cancel and use default path"
        echo ""
        echo -n "Select option (1-3): "
        read -r format_choice

        case "$format_choice" in
            1)
                # List partitions for selection
                local part_list=()
                while IFS= read -r part; do
                    part_list+=("$part")
                done < <(lsblk -n -o NAME "$device" | tail -n +2)

                if [ ${#part_list[@]} -eq 1 ]; then
                    partition_to_use="/dev/${part_list[0]}"
                    print_info "Using partition: $partition_to_use"
                else
                    echo ""
                    echo "Available partitions:"
                    for idx in "${!part_list[@]}"; do
                        local part_info=$(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "/dev/${part_list[$idx]}" 2>/dev/null | head -1)
                        echo "  [$((idx+1))] /dev/${part_list[$idx]} - $part_info"
                    done
                    echo ""
                    echo -n "Select partition (1-${#part_list[@]}): "
                    read -r part_sel

                    if [[ "$part_sel" =~ ^[0-9]+$ ]] && [ "$part_sel" -ge 1 ] && [ "$part_sel" -le "${#part_list[@]}" ]; then
                        partition_to_use="/dev/${part_list[$((part_sel-1))]}"
                    else
                        print_error "Invalid selection"
                        SELECTED_MEDIA_PATH="/mnt/media"
                        return
                    fi
                fi
                ;;
            2)
                format_drive "$device"
                partition_to_use="${device}1"
                # Handle NVMe naming convention
                if [[ "$device" == *"nvme"* ]]; then
                    partition_to_use="${device}p1"
                fi
                ;;
            *)
                print_info "Using default media path: /mnt/media"
                SELECTED_MEDIA_PATH="/mnt/media"
                return
                ;;
        esac
    else
        # No partitions - need to format
        print_warning "Drive has no partitions"
        echo -n "Format the drive? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            format_drive "$device"
            partition_to_use="${device}1"
            if [[ "$device" == *"nvme"* ]]; then
                partition_to_use="${device}p1"
            fi
        else
            print_info "Using default media path: /mnt/media"
            SELECTED_MEDIA_PATH="/mnt/media"
            return
        fi
    fi

    # Mount the partition
    mount_partition "$partition_to_use" "$mount_point"
}

# Format a drive with a single ext4 partition
format_drive() {
    local device="$1"

    print_warning "This will ERASE ALL DATA on $device!"
    echo -n "Type 'YES' to confirm: "
    read -r confirm

    if [ "$confirm" != "YES" ]; then
        print_info "Format cancelled"
        SELECTED_MEDIA_PATH="/mnt/media"
        return 1
    fi

    print_info "Formatting $device..."

    # Unmount any mounted partitions
    for part in $(lsblk -n -o NAME "$device" | tail -n +2); do
        umount "/dev/$part" 2>/dev/null || true
    done

    # Create new GPT partition table and single partition
    print_info "Creating partition table..."
    parted -s "$device" mklabel gpt
    parted -s "$device" mkpart primary ext4 0% 100%

    # Wait for partition to appear
    sleep 2

    # Determine partition name
    local partition="${device}1"
    if [[ "$device" == *"nvme"* ]]; then
        partition="${device}p1"
    fi

    # Format as ext4
    print_info "Formatting partition as ext4..."
    mkfs.ext4 -F -L "media" "$partition"

    print_success "Drive formatted successfully"
}

# Mount a partition
mount_partition() {
    local partition="$1"
    local mount_point="$2"

    print_info "Mounting $partition to $mount_point..."

    # Create mount point if needed
    if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
    fi

    # Check if already mounted elsewhere
    local current_mount=$(findmnt -n -o TARGET "$partition" 2>/dev/null)
    if [ -n "$current_mount" ]; then
        print_info "Partition already mounted at $current_mount"
        SELECTED_MEDIA_PATH="$current_mount"
        create_media_structure "$SELECTED_MEDIA_PATH"
        return
    fi

    # Mount the partition
    mount "$partition" "$mount_point"

    # Get UUID for fstab entry
    local uuid=$(blkid -s UUID -o value "$partition")

    # Add to fstab if not already present
    if ! grep -q "$uuid" /etc/fstab; then
        print_info "Adding mount to /etc/fstab for persistence..."
        echo "UUID=$uuid $mount_point ext4 defaults,nofail 0 2" >> /etc/fstab
        print_success "Added to /etc/fstab"
    else
        print_info "Mount already in /etc/fstab"
    fi

    SELECTED_MEDIA_PATH="$mount_point"
    print_success "Mounted at $SELECTED_MEDIA_PATH"

    create_media_structure "$SELECTED_MEDIA_PATH"
}

# Create media directory structure
create_media_structure() {
    local media_path="$1"

    print_info "Creating media directory structure..."

    local media_dirs=(
        "movies"
        "tv"
        "music"
        "books"
        "audiobooks"
        "podcasts"
        "photos"
        "downloads/complete"
        "downloads/incomplete"
        "downloads/watch"
        "transcode"
    )

    for dir in "${media_dirs[@]}"; do
        if [ ! -d "$media_path/$dir" ]; then
            mkdir -p "$media_path/$dir"
            print_success "Created $media_path/$dir"
        else
            print_info "Already exists: $media_path/$dir"
        fi
    done

    # Set ownership
    chown -R ${PUID:-1000}:${PGID:-1000} "$media_path"
    print_success "Media directory structure ready"
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

    # Auto-detect PUID and PGID from the user running sudo
    if [ -n "${SUDO_USER:-}" ]; then
        PUID=$(id -u "$SUDO_USER")
        PGID=$(id -g "$SUDO_USER")
        print_success "Auto-detected PUID=$PUID, PGID=$PGID (from user: $SUDO_USER)"
    else
        PUID=$(id -u)
        PGID=$(id -g)
        print_success "Auto-detected PUID=$PUID, PGID=$PGID"
    fi

    # Use the selected media path from drive selection, or prompt for manual entry
    if [ -n "${SELECTED_MEDIA_PATH:-}" ]; then
        MEDIA_ROOT="$SELECTED_MEDIA_PATH"
        print_info "Using selected media path: $MEDIA_ROOT"
    else
        echo -n "Media root path (default: /mnt/media): "
        read -r MEDIA_ROOT
        MEDIA_ROOT=${MEDIA_ROOT:-/mnt/media}
    fi

    echo -n "Your email address: "
    read -r EMAIL
    if [ -z "$EMAIL" ]; then
        print_warning "No email provided - some services may require this later"
        EMAIL=""
    fi

    # Ask about Cloudflare Tunnel for public access
    echo ""
    echo -n "Do you want to set up a domain with Cloudflare Tunnel for public access? (y/N): "
    read -r USE_CLOUDFLARE

    if [[ "$USE_CLOUDFLARE" =~ ^[Yy]$ ]]; then
        echo -n "Domain name: "
        read -r DOMAIN

        echo ""
        print_info "To get your Cloudflare Tunnel token:"
        echo "  1. Go to: https://one.dash.cloudflare.com/"
        echo "  2. Navigate to: Zero Trust → Networks → Tunnels"
        echo "  3. Create a tunnel and copy the token"
        echo ""
        echo -n "Cloudflare Tunnel Token: "
        read -r CLOUDFLARE_TUNNEL_TOKEN

        if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
            print_warning "No token provided - you can add it to .env later"
            CLOUDFLARE_TUNNEL_TOKEN="your_tunnel_token_here"
        fi
    else
        print_info "Skipping Cloudflare Tunnel setup"
        print_info "Services will only be accessible on your local network (and via Tailscale)"
        DOMAIN=""
        CLOUDFLARE_TUNNEL_TOKEN=""
    fi


    echo ""
    print_info "TMDB API Key is used by Jellyseerr for media discovery"
    echo "  Get one free at: https://www.themoviedb.org/settings/api"
    echo ""
    echo -n "TMDB API Key (press Enter to skip): "
    read -r TMDB_API_KEY
    if [ -z "$TMDB_API_KEY" ]; then
        print_warning "No TMDB key - Jellyseerr will need this configured later"
        TMDB_API_KEY=""
    fi

    # Optional features
    print_section "Optional Features"

    echo -n "Enable audiobook/ebook support? (Audiobookshelf + Calibre-Web) (Y/n): "
    read -r USE_BOOKS
    if [[ "$USE_BOOKS" =~ ^[Nn]$ ]]; then
        ENABLE_BOOKS=false
        print_info "Audiobook/ebook services disabled"
    else
        ENABLE_BOOKS=true
        print_success "Audiobook/ebook services enabled"
    fi

    echo -n "Enable Open Voice OS? (Local voice assistant) (y/N): "
    read -r USE_OVOS
    if [[ "$USE_OVOS" =~ ^[Yy]$ ]]; then
        ENABLE_OVOS=true
        print_success "Open Voice OS enabled"
    else
        ENABLE_OVOS=false
        print_info "Open Voice OS disabled"
    fi

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
EMAIL=${EMAIL}

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

# SABnzbd API Key (optional - configure after SABnzbd is set up)
SABNZBD_API_KEY=
EOF

    # Add Cloudflare section if configured
    if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ] && [ "$CLOUDFLARE_TUNNEL_TOKEN" != "your_tunnel_token_here" ]; then
        cat >> .env << EOF

# Cloudflare Tunnel (Public Access)
DOMAIN=${DOMAIN}
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
EOF
    elif [ -n "$DOMAIN" ]; then
        cat >> .env << EOF

# Cloudflare Tunnel (Not configured - add token to enable)
DOMAIN=${DOMAIN}
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-your_tunnel_token_here}
EOF
    fi

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

    # Create/update docker-compose.override.yml for disabled services
    create_compose_override
}

# Create docker-compose.override.yml to disable unused services
create_compose_override() {
    print_info "Configuring service profiles..."

    cat > docker-compose.override.yml << 'EOF'
# Auto-generated by setup-homelab.sh
# This file disables optional services using Docker Compose profiles
# Services with profiles won't start unless explicitly enabled
# Re-run setup-homelab.sh or edit this file to change enabled services

services:
EOF

    # Disable Cloudflare if not configured
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ] || [ "$CLOUDFLARE_TUNNEL_TOKEN" = "your_tunnel_token_here" ]; then
        cat >> docker-compose.override.yml << 'EOF'
  # Cloudflare Tunnel - disabled (not configured)
  # To enable: add CLOUDFLARE_TUNNEL_TOKEN to .env and remove this section
  cloudflared:
    profiles: ["cloudflare"]
EOF
        print_info "Cloudflare Tunnel: disabled"
    else
        print_success "Cloudflare Tunnel: enabled"
    fi

    # Disable books services if not wanted
    if [ "$ENABLE_BOOKS" = false ]; then
        cat >> docker-compose.override.yml << 'EOF'

  # Audiobook/Ebook services - disabled
  # To enable: remove this section and restart
  audiobookshelf:
    profiles: ["books"]
  calibre-web:
    profiles: ["books"]
EOF
        print_info "Audiobooks/Ebooks: disabled"
    else
        print_success "Audiobooks/Ebooks: enabled"
    fi

    # Disable OVOS if not wanted
    if [ "$ENABLE_OVOS" = false ]; then
        cat >> docker-compose.override.yml << 'EOF'

  # OVOS (Open Voice OS) - disabled
  # To enable: docker compose --profile ovos up -d
  ovos-messagebus:
    profiles: ["ovos"]
  ovos-phal:
    profiles: ["ovos"]
  ovos-audio:
    profiles: ["ovos"]
  ovos-listener:
    profiles: ["ovos"]
  ovos-core:
    profiles: ["ovos"]
  ovos-gui:
    profiles: ["ovos"]
EOF
        print_info "Open Voice OS: disabled"
    else
        print_success "Open Voice OS: enabled"
    fi

    print_success "docker-compose.override.yml created"
}

# Create data directories
create_directories() {
    print_section "Creating Data Directories"

    local dirs=(
        "data/homarr/appdata"
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
        "data/recyclarr/config/cache"
        "data/qbittorrent/config"
        "data/sabnzbd/config"
        "data/tdarr/server"
        "data/tdarr/configs"
        "data/tdarr/logs"
        "data/tdarr/temp"
        "data/arm/config"
        "data/arm/db"
        "data/arm/logs"
        "data/arm/media"
        "data/immich"
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

        # Fix ARM config file permissions for web UI write access
        if [ -f "data/arm/config/arm.yaml" ]; then
            chmod 664 data/arm/config/arm.yaml
            print_success "ARM config file permissions set to 664"
        fi
    fi

    print_success "All data directories ready"
}

# Setup Open Voice OS configuration
setup_ovos() {
    # Skip if OVOS is disabled
    if [ "$ENABLE_OVOS" = false ]; then
        return
    fi

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
        print_warning "OVOS audio services may not work without audio device access"
        print_info "Ensure your user has access to audio devices"
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

# Install Tailscale on the host for remote access
setup_tailscale() {
    print_section "Setting Up Tailscale"

    # Check if Tailscale is already installed
    if command -v tailscale &> /dev/null; then
        print_success "Tailscale is already installed"
        local ts_status=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4)
        if [ "$ts_status" == "Running" ]; then
            print_success "Tailscale is connected"
            tailscale status | head -5
        else
            print_info "Tailscale is installed but not connected"
            echo -n "Connect to Tailscale now? (Y/n): "
            read -r response
            if [[ ! "$response" =~ ^[Nn]$ ]]; then
                print_info "Starting Tailscale authentication..."
                tailscale up --hostname=homelab
                print_success "Tailscale connected"
            fi
        fi
        return
    fi

    echo -n "Install Tailscale for remote access? (Y/n): "
    read -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        print_info "Skipping Tailscale installation"
        return
    fi

    print_info "Installing Tailscale..."

    # Install using official script
    curl -fsSL https://tailscale.com/install.sh | sh

    if command -v tailscale &> /dev/null; then
        print_success "Tailscale installed successfully"

        # Enable and start the service
        systemctl enable --now tailscaled

        print_info "Starting Tailscale authentication..."
        print_info "A browser window will open for authentication."
        echo ""

        # Start Tailscale with a hostname
        tailscale up --hostname=homelab

        print_success "Tailscale is now running"
        print_info "Your Tailscale IP:"
        tailscale ip -4
        echo ""
        print_info "Access services remotely at: http://$(tailscale ip -4):PORT"
    else
        print_error "Tailscale installation failed"
        print_info "You can install manually later: https://tailscale.com/download/linux"
    fi
}

# Setup ARM (Automatic Ripping Machine) udev auto-detection
setup_arm_udev() {
    print_section "Setting Up ARM Automatic Disc Detection"

    # Check if optical drive exists
    if [ ! -e /dev/sr0 ]; then
        print_warning "No optical drive found at /dev/sr0"
        print_info "Skipping ARM udev configuration"
        return
    fi

    print_success "Optical drive found at /dev/sr0"

    # Create ARM scripts directory
    if [ ! -d "/opt/arm/scripts" ]; then
        print_info "Creating /opt/arm/scripts directory..."
        sudo mkdir -p /opt/arm/scripts
    fi

    # Create udev wrapper script for docker-compose
    print_info "Creating ARM udev wrapper script..."
    sudo tee /opt/arm/scripts/docker_arm_wrapper.sh > /dev/null << 'WRAPPER_EOF'
#!/bin/bash
# ARM udev wrapper for docker-compose
# This script is called by udev when an optical disc is inserted

set -euo pipefail

DEVNAME="$1"
CONTAINER_NAME="arm"

# Find homelab directory - check common locations
if [ -f "/home/*/homelab/docker-compose.yml" ]; then
    HOMELAB_DIR=$(dirname $(ls /home/*/homelab/docker-compose.yml 2>/dev/null | head -1))
elif [ -f "/opt/homelab/docker-compose.yml" ]; then
    HOMELAB_DIR="/opt/homelab"
else
    echo "$(date) [ARM] Could not find homelab directory" >> /var/log/arm-wrapper.log
    exit 1
fi

# Wait for disc to be fully readable
sleep 5

echo "$(date) [ARM] Entering docker wrapper for ${DEVNAME}" >> /var/log/arm-wrapper.log

# Exit if udev properties not available yet
if [[ -z "${!ID_CDROM_MEDIA_*}" ]] ; then
    echo "$(date) [ARM] Disc not ready yet, exiting" >> /var/log/arm-wrapper.log
    exit 0
fi

# Fix device path if needed
if [[ ! -b "${DEVNAME}" && -b "/dev/${DEVNAME}" ]] ; then
    DEVNAME="/dev/${DEVNAME}"
fi

# Get disc type and label from udev
if [[ -z "${!ID_CDROM_MEDIA_*}" ]] ; then
    eval "$(udevadm info --query=env --export "${DEVNAME}")"
fi

# Determine disc type (use defaults to avoid unbound variable errors)
if [ "${ID_CDROM_MEDIA_DVD:-0}" == "1" ]; then
    DISC_TYPE="DVD"
elif [ "${ID_CDROM_MEDIA_BD:-0}" == "1" ]; then
    DISC_TYPE="Blu-ray"
elif [ "${ID_CDROM_MEDIA_CD:-0}" == "1" ] || [ "${ID_CDROM_MEDIA_CD_R:-0}" == "1" ] || [ "${ID_CDROM_MEDIA_CD_RW:-0}" == "1" ]; then
    DISC_TYPE="CD"
elif [ -n "${ID_FS_TYPE:-}" ]; then
    DISC_TYPE="Data"
else
    echo "$(date) [ARM] Unknown disc type, exiting" >> /var/log/arm-wrapper.log
    exit 0
fi

echo "$(date) [ARM] Detected ${DISC_TYPE} disc (label: ${ID_FS_LABEL:-unknown}) on ${DEVNAME}" >> /var/log/arm-wrapper.log

# Start ARM in the existing docker-compose container
# Export udev environment variables so ARM can read disc properties
cd "${HOMELAB_DIR}"
docker compose exec -T \
    -e ID_CDROM_MEDIA_DVD="${ID_CDROM_MEDIA_DVD:-0}" \
    -e ID_CDROM_MEDIA_BD="${ID_CDROM_MEDIA_BD:-0}" \
    -e ID_CDROM_MEDIA_CD="${ID_CDROM_MEDIA_CD:-0}" \
    -e ID_FS_LABEL="${ID_FS_LABEL:-}" \
    "${CONTAINER_NAME}" \
    /opt/arm/scripts/docker/docker_arm_wrapper.sh "${DEVNAME##*/}" \
    >> /var/log/arm-wrapper.log 2>&1

echo "$(date) [ARM] Rip started successfully" >> /var/log/arm-wrapper.log
WRAPPER_EOF

    sudo chmod +x /opt/arm/scripts/docker_arm_wrapper.sh
    print_success "ARM wrapper script created at /opt/arm/scripts/docker_arm_wrapper.sh"

    # Create udev rule
    print_info "Creating udev rule..."
    sudo tee /etc/udev/rules.d/99-arm-docker.rules > /dev/null << 'UDEV_EOF'
# ARM (Automatic Ripping Machine) udev rule for docker-compose
# Triggers ARM wrapper when optical disc is inserted
ACTION=="change", SUBSYSTEM=="block", ENV{DISK_MEDIA_CHANGE}=="1", ENV{ID_TYPE}=="cd", RUN+="/opt/arm/scripts/docker_arm_wrapper.sh %k"
UDEV_EOF

    print_success "Udev rule created at /etc/udev/rules.d/99-arm-docker.rules"

    # Reload udev rules
    print_info "Reloading udev rules..."
    if sudo udevadm control --reload 2>/dev/null; then
        print_success "Udev rules reloaded"
    else
        print_warning "Could not reload udev rules"
        print_info "Udev rules will be active after reboot or manual reload"
    fi

    print_success "ARM automatic disc detection configured!"
    print_info "Insert a disc to test auto-ripping"
    print_info "Monitor with: tail -f /var/log/arm-wrapper.log"
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

    # Set longer timeout for slow connections
    export COMPOSE_HTTP_TIMEOUT=120

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

    local databases=("immich")

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

    # Get IPs
    local ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
    local lan_ip=$(hostname -I | awk '{print $1}')

    # Check if Cloudflare is configured
    local cf_configured=false
    if grep -q "^CLOUDFLARE_TUNNEL_TOKEN=" .env 2>/dev/null; then
        local token=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" .env | cut -d'=' -f2)
        if [ -n "$token" ] && [ "$token" != "your_tunnel_token_here" ]; then
            cf_configured=true
        fi
    fi

    # Get domain from .env
    local domain=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d'=' -f2)

    if [ "$cf_configured" = true ] && [ -n "$domain" ]; then
        echo -e "${GREEN}Public Services (via Cloudflare Tunnel):${NC}"
        echo "  Homarr:         https://homarr.${domain}"
        echo "  Jellyfin:       https://jellyfin.${domain}"
        echo "  Jellyseerr:     https://jellyseerr.${domain}"
        echo "  Immich:         https://photos.${domain}"
        if [ "$ENABLE_BOOKS" = true ]; then
            echo "  Audiobookshelf: https://audiobooks.${domain}"
            echo "  Calibre-web:    https://books.${domain}"
        fi
        echo ""
    fi

    echo -e "${BLUE}All Services (LAN: ${lan_ip}):${NC}"
    echo "  Homarr:         http://${lan_ip}:7575"
    echo "  Jellyfin:       http://${lan_ip}:8096"
    echo "  Jellyseerr:     http://${lan_ip}:5055"
    echo "  Immich:         http://${lan_ip}:2283"
    if [ "$ENABLE_BOOKS" = true ]; then
        echo "  Audiobookshelf: http://${lan_ip}:13378"
        echo "  Calibre-web:    http://${lan_ip}:8083"
    fi
    echo "  Sonarr:         http://${lan_ip}:8989"
    echo "  Radarr:         http://${lan_ip}:7878"
    echo "  Prowlarr:       http://${lan_ip}:9696"
    echo "  Bazarr:         http://${lan_ip}:6767"
    echo "  Lidarr:         http://${lan_ip}:8686"
    echo "  qBittorrent:    http://${lan_ip}:8080"
    echo "  SABnzbd:        http://${lan_ip}:8085"
    echo "  Tdarr:          http://${lan_ip}:8265"
    echo "  ARM:            http://${lan_ip}:8090"
    echo "  Uptime Kuma:    http://${lan_ip}:3001"
    if [ "$ENABLE_OVOS" = true ]; then
        echo "  OVOS GUI:       http://${lan_ip}:8484"
    fi

    echo -e "\n${YELLOW}Next Steps:${NC}"
    if [ "$cf_configured" = true ]; then
        echo "  1. Configure Cloudflare Tunnel routes (see docs/networking.md)"
        echo "  2. Configure media libraries in *arr apps"
        echo "  3. Configure ARM for Blu-ray ripping: http://${lan_ip}:8090"
    else
        echo "  1. Configure media libraries in *arr apps"
        echo "  2. Configure ARM for Blu-ray ripping: http://${lan_ip}:8090"
        echo "  3. (Optional) Set up Cloudflare Tunnel for public access"
    fi

    if [ -n "$ts_ip" ]; then
        echo -e "\n${GREEN}Tailscale Remote Access:${NC}"
        echo "  Access any service remotely via: http://${ts_ip}:PORT"
    fi

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
    select_media_drive
    generate_env
    create_directories
    setup_tailscale
    setup_ovos
    setup_arm_udev
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
