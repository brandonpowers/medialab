#!/bin/bash
set -e

# Homelab Automated Setup Script
# This script automates the complete setup of your homelab infrastructure
# Focused on video streaming: Jellyfin, *arr stack, ARM, Tdarr

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   HOMELAB AUTOMATED SETUP - VIDEO STREAMING               ║${NC}"
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
    apt-get install -y ca-certificates curl jq &>/dev/null
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
# Helper function to get a value from .env file
get_env_value() {
    local key="$1"
    if [ -f .env ]; then
        grep "^${key}=" .env 2>/dev/null | cut -d'=' -f2- | head -1
    fi
}

# Helper function to set a value in .env file (only if not already set or if forced)
set_env_value() {
    local key="$1"
    local value="$2"
    local force="${3:-false}"

    if [ ! -f .env ]; then
        # Create .env with header if it doesn't exist
        cat > .env << EOF
# ============================================
# HOMELAB ENVIRONMENT CONFIGURATION
# Generated: $(date)
# Video Streaming Focus
# ============================================

EOF
    fi

    local existing=$(get_env_value "$key")

    if [ -z "$existing" ]; then
        # Key doesn't exist, append it
        echo "${key}=${value}" >> .env
        return 0
    elif [ "$force" = "true" ]; then
        # Force update - replace existing value
        sed -i "s|^${key}=.*|${key}=${value}|" .env
        return 0
    fi
    # Key exists and not forcing, skip
    return 1
}

generate_env() {
    print_section "Generating Environment Configuration"

    local is_update=false

    # Check if .env exists
    if [ -f .env ]; then
        is_update=true
        print_info "Existing .env found - will preserve existing values"
        print_info "Only missing variables will be added"
        echo ""

        # Source existing values so we can use them
        set -a
        source .env
        set +a

        backup_env
    fi

    # --- System Configuration ---

    # Timezone
    local existing_tz=$(get_env_value "TZ")
    if [ -z "$existing_tz" ]; then
        echo -n "Timezone (default: America/Chicago): "
        read -r TZ
        TZ=${TZ:-America/Chicago}
        set_env_value "TZ" "$TZ"
        print_success "Set TZ=$TZ"
    else
        TZ="$existing_tz"
        print_info "Using existing TZ=$TZ"
    fi

    # PUID/PGID - auto-detect
    local existing_puid=$(get_env_value "PUID")
    if [ -z "$existing_puid" ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            PUID=$(id -u "$SUDO_USER")
            PGID=$(id -g "$SUDO_USER")
        else
            PUID=$(id -u)
            PGID=$(id -g)
        fi
        set_env_value "PUID" "$PUID"
        set_env_value "PGID" "$PGID"
        print_success "Set PUID=$PUID, PGID=$PGID"
    else
        PUID="$existing_puid"
        PGID=$(get_env_value "PGID")
        print_info "Using existing PUID=$PUID, PGID=$PGID"
    fi

    # Media root
    local existing_media=$(get_env_value "MEDIA_ROOT")
    if [ -z "$existing_media" ]; then
        if [ -n "${SELECTED_MEDIA_PATH:-}" ]; then
            MEDIA_ROOT="$SELECTED_MEDIA_PATH"
        else
            echo -n "Media root path (default: /mnt/media): "
            read -r MEDIA_ROOT
            MEDIA_ROOT=${MEDIA_ROOT:-/mnt/media}
            create_media_structure "$MEDIA_ROOT"
        fi
        set_env_value "MEDIA_ROOT" "$MEDIA_ROOT"
        print_success "Set MEDIA_ROOT=$MEDIA_ROOT"
    else
        MEDIA_ROOT="$existing_media"
        print_info "Using existing MEDIA_ROOT=$MEDIA_ROOT"
    fi

    # Email
    local existing_email=$(get_env_value "EMAIL")
    if [ -z "$existing_email" ]; then
        echo -n "Your email address (press Enter to skip): "
        read -r EMAIL
        set_env_value "EMAIL" "${EMAIL:-}"
        [ -n "$EMAIL" ] && print_success "Set EMAIL=$EMAIL" || print_info "Skipped EMAIL"
    else
        EMAIL="$existing_email"
        print_info "Using existing EMAIL=$EMAIL"
    fi

    # --- Homarr Encryption Key ---
    local existing_homarr=$(get_env_value "HOMARR_ENCRYPTION_KEY")
    if [ -z "$existing_homarr" ]; then
        HOMARR_ENCRYPTION_KEY=$(openssl rand -hex 32)
        set_env_value "HOMARR_ENCRYPTION_KEY" "$HOMARR_ENCRYPTION_KEY"
        print_success "Generated new HOMARR_ENCRYPTION_KEY"

        # Save to passwords file
        cat > .passwords.txt << EOF
HOMELAB PASSWORDS - $(date)
KEEP THIS FILE SECURE!

Homarr Encryption Key: ${HOMARR_ENCRYPTION_KEY}

These passwords have been added to .env
Consider storing them in a password manager and deleting this file.
EOF
        chmod 600 .passwords.txt
        print_warning "New passwords saved to .passwords.txt"
    else
        HOMARR_ENCRYPTION_KEY="$existing_homarr"
        print_info "Using existing HOMARR_ENCRYPTION_KEY"
    fi

    # --- API Keys ---

    # TMDB
    local existing_tmdb=$(get_env_value "TMDB_API_KEY")
    if [ -z "$existing_tmdb" ]; then
        echo ""
        print_info "TMDB API Key is used by Jellyseerr for media discovery"
        echo "  Get one free at: https://www.themoviedb.org/settings/api"
        echo ""
        echo -n "TMDB API Key (press Enter to skip): "
        read -r TMDB_API_KEY
        set_env_value "TMDB_API_KEY" "${TMDB_API_KEY:-}"
        [ -n "$TMDB_API_KEY" ] && print_success "Set TMDB_API_KEY" || print_info "Skipped TMDB_API_KEY"
    else
        TMDB_API_KEY="$existing_tmdb"
        print_info "Using existing TMDB_API_KEY"
    fi

    # Recyclarr API keys - add placeholders if missing
    set_env_value "SONARR_API_KEY" "your_sonarr_api_key_here"
    set_env_value "RADARR_API_KEY" "your_radarr_api_key_here"
    set_env_value "SABNZBD_API_KEY" ""

    # --- Cloudflare Tunnel ---
    local existing_cf_token=$(get_env_value "CLOUDFLARE_TUNNEL_TOKEN")
    if [ -z "$existing_cf_token" ] || [ "$existing_cf_token" = "your_tunnel_token_here" ]; then
        echo ""
        echo -n "Do you want to set up a domain with Cloudflare Tunnel for public access? (y/N): "
        read -r USE_CLOUDFLARE

        if [[ "$USE_CLOUDFLARE" =~ ^[Yy]$ ]]; then
            local existing_domain=$(get_env_value "DOMAIN")
            if [ -z "$existing_domain" ]; then
                echo -n "Domain name: "
                read -r DOMAIN
                set_env_value "DOMAIN" "$DOMAIN"
            else
                DOMAIN="$existing_domain"
                print_info "Using existing DOMAIN=$DOMAIN"
            fi

            echo ""
            print_info "To get your Cloudflare Tunnel token:"
            echo "  1. Go to: https://one.dash.cloudflare.com/"
            echo "  2. Navigate to: Zero Trust → Networks → Tunnels"
            echo "  3. Create a tunnel and copy the token"
            echo ""
            echo -n "Cloudflare Tunnel Token: "
            read -r CLOUDFLARE_TUNNEL_TOKEN

            if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
                set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$CLOUDFLARE_TUNNEL_TOKEN" "true"
                print_success "Set CLOUDFLARE_TUNNEL_TOKEN"
            else
                set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "your_tunnel_token_here"
                print_warning "No token provided - you can add it to .env later"
            fi
        else
            print_info "Skipping Cloudflare Tunnel setup"
            print_info "Services will only be accessible on your local network"
            set_env_value "DOMAIN" ""
            set_env_value "CLOUDFLARE_TUNNEL_TOKEN" ""
        fi
    else
        CLOUDFLARE_TUNNEL_TOKEN="$existing_cf_token"
        DOMAIN=$(get_env_value "DOMAIN")
        print_info "Using existing Cloudflare Tunnel configuration"
    fi

    echo ""
    if [ "$is_update" = true ]; then
        print_success ".env file updated (existing values preserved)"
    else
        print_success ".env file created successfully"
    fi
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

    print_success "docker-compose.override.yml created"
}

# Create data directories
create_directories() {
    print_section "Creating Data Directories"

    # Ensure PUID/PGID are set (use values from generate_env or defaults)
    local puid=${PUID:-1000}
    local pgid=${PGID:-1000}

    local dirs=(
        "data/homarr/appdata"
        "data/jellyfin/config"
        "data/jellyfin/cache"
        "data/jellyseerr/config"
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
        chown -R ${puid}:${pgid} data/arm
        print_success "ARM directory ownership set to ${puid}:${pgid}"

        # Fix ARM config file permissions for web UI write access
        if [ -f "data/arm/config/arm.yaml" ]; then
            chmod 664 data/arm/config/arm.yaml
            print_success "ARM config file permissions set to 664"
        fi
    fi

    print_success "All data directories ready"
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

    # Create ARM udev wrapper script
    # This script passes udev environment variables into the ARM container
    print_info "Creating ARM udev wrapper script..."
    cat > /usr/local/bin/arm-udev-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
# ARM udev wrapper - passes udev environment variables to ARM container
# Called by udev when an optical disc is inserted

DEVNAME="$1"

# Export udev environment variables to the container
# The ARM docker_arm_wrapper.sh script checks these to determine disc type
/usr/bin/docker exec -d \
  -e "ID_CDROM_MEDIA_BD=${ID_CDROM_MEDIA_BD}" \
  -e "ID_CDROM_MEDIA_DVD=${ID_CDROM_MEDIA_DVD}" \
  -e "ID_CDROM_MEDIA_CD=${ID_CDROM_MEDIA_CD}" \
  -e "ID_CDROM_MEDIA_CD_R=${ID_CDROM_MEDIA_CD_R}" \
  -e "ID_CDROM_MEDIA_CD_RW=${ID_CDROM_MEDIA_CD_RW}" \
  -e "ID_FS_TYPE=${ID_FS_TYPE}" \
  -e "ID_FS_LABEL=${ID_FS_LABEL}" \
  arm /opt/arm/scripts/docker/docker_arm_wrapper.sh "$DEVNAME"
WRAPPER_EOF

    chmod +x /usr/local/bin/arm-udev-wrapper.sh
    print_success "ARM wrapper script created at /usr/local/bin/arm-udev-wrapper.sh"

    # Create udev rule (must be single line to avoid parsing errors)
    print_info "Creating udev rule..."
    echo 'ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr[0-9]*", ENV{ID_CDROM_MEDIA}=="1", RUN+="/usr/local/bin/arm-udev-wrapper.sh %k"' > /etc/udev/rules.d/99-arm.rules

    print_success "Udev rule created at /etc/udev/rules.d/99-arm.rules"

    # Reload udev rules
    print_info "Reloading udev rules..."
    if udevadm control --reload-rules 2>/dev/null; then
        print_success "Udev rules reloaded"
    else
        print_warning "Could not reload udev rules"
        print_info "Udev rules will be active after reboot or manual reload"
    fi

    print_success "ARM automatic disc detection configured!"
    print_info "Insert a disc to test auto-ripping"
    print_info "Monitor with: docker logs -f arm"
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

# Show service status
show_status() {
    print_section "Service Status"

    docker compose ps
}

# Show access information
show_access_info() {
    print_section "Access Information"

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
        echo ""
    fi

    echo -e "${BLUE}All Services (LAN: ${lan_ip}):${NC}"
    echo "  Homarr:         http://${lan_ip}:7575"
    echo "  Jellyfin:       http://${lan_ip}:8096"
    echo "  Jellyseerr:     http://${lan_ip}:5055"
    echo "  Sonarr:         http://${lan_ip}:8989"
    echo "  Radarr:         http://${lan_ip}:7878"
    echo "  Lidarr:         http://${lan_ip}:8686"
    echo "  Prowlarr:       http://${lan_ip}:9696"
    echo "  Bazarr:         http://${lan_ip}:6767"
    echo "  qBittorrent:    http://${lan_ip}:8080"
    echo "  SABnzbd:        http://${lan_ip}:8085"
    echo "  Tdarr:          http://${lan_ip}:8265"
    echo "  ARM:            http://${lan_ip}:8090"
    echo "  Uptime Kuma:    http://${lan_ip}:3001"

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
    create_compose_override
    create_directories
    setup_arm_udev
    validate_compose
    pull_images
    start_services
    sleep 5  # Give services a moment to initialize
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
