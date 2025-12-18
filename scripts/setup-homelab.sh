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

# ============================================
# AUTO-DETECTION FUNCTIONS
# ============================================

# Auto-detect system timezone
detect_timezone() {
    local tz=""

    # Method 1: timedatectl (systemd)
    if command -v timedatectl &>/dev/null; then
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
    fi

    # Method 2: /etc/timezone file
    if [ -z "$tz" ] && [ -f /etc/timezone ]; then
        tz=$(cat /etc/timezone 2>/dev/null | tr -d '[:space:]')
    fi

    # Method 3: /etc/localtime symlink
    if [ -z "$tz" ] && [ -L /etc/localtime ]; then
        tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    fi

    # Fallback
    echo "${tz:-America/Chicago}"
}

# Auto-detect optical drives (Blu-ray/DVD/CD)
detect_optical_drives() {
    local drives=()

    # Scan for sr* devices (optical drives)
    for dev in /dev/sr*; do
        if [ -e "$dev" ]; then
            drives+=("$dev")
        fi
    done

    # Return space-separated list of drives
    echo "${drives[*]}"
}

# Get optical drive info (for display)
get_optical_drive_info() {
    local device="$1"
    local info=""

    # Try to get device model from udevadm
    if command -v udevadm &>/dev/null; then
        info=$(udevadm info --query=property --name="$device" 2>/dev/null | grep -E "ID_MODEL=|ID_VENDOR=" | head -2 | cut -d'=' -f2 | tr '\n' ' ')
    fi

    # Fallback: check if it's a Blu-ray drive
    if [ -z "$info" ]; then
        if [ -e "/sys/class/block/$(basename "$device")/device/model" ]; then
            info=$(cat "/sys/class/block/$(basename "$device")/device/model" 2>/dev/null)
        fi
    fi

    echo "${info:-Unknown optical drive}"
}

# Find the corresponding SCSI generic device for an optical drive
find_sg_device() {
    local sr_device="$1"
    local sr_name=$(basename "$sr_device")

    # Method 1: Check sysfs for the sg device
    if [ -d "/sys/class/block/$sr_name/device/scsi_generic" ]; then
        local sg_name=$(ls "/sys/class/block/$sr_name/device/scsi_generic" 2>/dev/null | head -1)
        if [ -n "$sg_name" ]; then
            echo "/dev/$sg_name"
            return
        fi
    fi

    # Method 2: Find sg device with matching SCSI address
    local scsi_host=$(readlink -f "/sys/class/block/$sr_name/device" 2>/dev/null | grep -oP '\d+:\d+:\d+:\d+' | head -1)
    if [ -n "$scsi_host" ]; then
        for sg in /sys/class/scsi_generic/sg*; do
            local sg_scsi=$(readlink -f "$sg/device" 2>/dev/null | grep -oP '\d+:\d+:\d+:\d+' | head -1)
            if [ "$sg_scsi" = "$scsi_host" ]; then
                echo "/dev/$(basename "$sg")"
                return
            fi
        done
    fi

    # Fallback: assume sg device number matches sr device number
    local num=$(echo "$sr_name" | grep -oP '\d+$')
    if [ -e "/dev/sg$((num+1))" ]; then
        echo "/dev/sg$((num+1))"
    fi
}

# Auto-detect the largest non-system storage drive
detect_largest_storage_drive() {
    local largest_drive=""
    local largest_size=0

    # Get list of block devices, excluding loop devices and the root filesystem
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local size_bytes=$(echo "$line" | awk '{print $2}')
        local mountpoint=$(echo "$line" | awk '{print $3}')

        # Skip if it's the root filesystem
        if [ "$mountpoint" = "/" ]; then
            continue
        fi

        # Skip if size is empty or zero
        if [ -z "$size_bytes" ] || [ "$size_bytes" = "0" ]; then
            continue
        fi

        # Check if this is larger than current largest
        if [ "$size_bytes" -gt "$largest_size" ]; then
            largest_size=$size_bytes
            largest_drive="/dev/$name"
        fi
    done < <(lsblk -d -b -n -o NAME,SIZE,MOUNTPOINT 2>/dev/null | grep -E "^(sd|nvme|vd)")

    echo "$largest_drive"
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1099511627776 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1099511627776}")TB"
    elif [ "$bytes" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}")GB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
    fi
}

# Auto-detect GPU type for hardware transcoding
detect_gpu_type() {
    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -iE "vga|3d|display" || echo "")

    # Check for AMD GPU (VAAPI)
    if echo "$gpu_info" | grep -qi "amd\|radeon"; then
        echo "vaapi"
        return
    fi

    # Check for NVIDIA GPU (NVENC)
    if echo "$gpu_info" | grep -qi "nvidia"; then
        echo "nvenc"
        return
    fi

    # Check for Intel integrated GPU (QSV)
    if echo "$gpu_info" | grep -qi "intel"; then
        echo "qsv"
        return
    fi

    # Fallback to CPU encoding
    echo "cpu"
}

# Get human-readable GPU name
get_gpu_name() {
    local hw_type="$1"
    case "$hw_type" in
        vaapi) echo "AMD (VAAPI)" ;;
        nvenc) echo "NVIDIA (NVENC)" ;;
        qsv)   echo "Intel (QuickSync)" ;;
        cpu)   echo "CPU (software)" ;;
        *)     echo "Unknown" ;;
    esac
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
    local drive_sizes=()
    local recommended_idx=-1
    local largest_size=0

    # Read drives into array
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local size_bytes=$(lsblk -d -b -n -o SIZE "/dev/$name" 2>/dev/null)
        local type=$(echo "$line" | awk '{print $3}')
        local model=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | xargs)

        # Get mount point from partitions (disks themselves aren't mounted, partitions are)
        # Prioritize fstab entries over automount locations
        local mountpoint=""
        local first_partition=$(lsblk -n -o NAME "/dev/$name" 2>/dev/null | tail -n +2 | head -1)
        if [ -n "$first_partition" ]; then
            # Use get_preferred_mount if available, otherwise fall back to lsblk
            mountpoint=$(get_preferred_mount "/dev/$first_partition" 2>/dev/null)
        fi
        # Fall back to lsblk if get_preferred_mount returned nothing
        if [ -z "$mountpoint" ]; then
            mountpoint=$(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v "^$" | head -1)
        fi

        # Skip if it's the boot/root drive
        if [ "$mountpoint" == "/" ] || [ "$mountpoint" == "/boot" ] || [ "$mountpoint" == "/boot/efi" ]; then
            continue
        fi

        drives+=("$name")
        drive_info+=("$size|$type|$mountpoint|$model")
        drive_sizes+=("$size_bytes")

        # Track largest drive for recommendation
        if [ -n "$size_bytes" ] && [ "$size_bytes" -gt "$largest_size" ]; then
            largest_size=$size_bytes
            recommended_idx=${#drives[@]}
            recommended_idx=$((recommended_idx - 1))
        fi
    done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n | grep -E "^(sd|nvme|vd)" | grep -v "loop")

    if [ ${#drives[@]} -eq 0 ]; then
        print_warning "No additional drives found"
        print_info "Using default media path: /mnt/media"
        SELECTED_MEDIA_PATH="/mnt/media"
        return
    fi

    # If only one non-system drive and it's large enough (>100GB), auto-select it
    if [ ${#drives[@]} -eq 1 ] && [ "$largest_size" -gt 107374182400 ]; then
        local name="${drives[0]}"
        IFS='|' read -r size type mountpoint model <<< "${drive_info[0]}"
        print_success "Auto-detected media drive: /dev/$name ($size)"
        print_info "Model: ${model:-Unknown}"
        setup_media_drive "/dev/$name" "$mountpoint"
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
        local rec_marker=""
        if [ "$idx" -eq "$recommended_idx" ]; then
            rec_marker=" (Recommended - largest)"
        fi
        printf "  %-4s %-12s %-10s %-8s %-20s %s%s\n" "[$((idx+1))]" "/dev/$name" "$size" "$type" "$mountpoint" "$model" "$rec_marker"
    done

    echo ""
    printf "  %-4s %-12s\n" "[S]" "Skip - use default path (/mnt/media)"
    echo ""

    # Default to recommended drive
    local default_selection=$((recommended_idx + 1))
    if [ $recommended_idx -ge 0 ]; then
        print_info "Press Enter to use recommended drive, or select another option"
        echo ""
    fi

    # Get user selection
    while true; do
        if [ $recommended_idx -ge 0 ]; then
            echo -n "Select a drive for media storage [${default_selection}]: "
        else
            echo -n "Select a drive for media storage (1-${#drives[@]} or S to skip): "
        fi
        read -r selection

        # Default to recommended if just Enter pressed
        if [ -z "$selection" ] && [ $recommended_idx -ge 0 ]; then
            selection=$default_selection
        fi

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

# Get the preferred mount point for a partition
# Prioritizes fstab entries over automount locations (e.g., /media/*)
get_preferred_mount() {
    local partition="$1"

    # Get UUID for fstab lookup
    local uuid=$(blkid -s UUID -o value "$partition" 2>/dev/null)

    # Check fstab for configured mount point (preferred)
    if [ -n "$uuid" ]; then
        local fstab_mount=$(grep -E "UUID=$uuid|$partition" /etc/fstab 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$fstab_mount" ] && [ "$fstab_mount" != "none" ] && [ "$fstab_mount" != "swap" ]; then
            echo "$fstab_mount"
            return
        fi
    fi

    # Fall back to current mount point, but warn if it's an automount location
    local current_mount=$(findmnt -n -o TARGET "$partition" 2>/dev/null)
    if [ -n "$current_mount" ]; then
        # Warn if this looks like a GNOME/udisks automount path
        if [[ "$current_mount" == /media/* ]] && [[ "$current_mount" != /media/brandon/* ]]; then
            print_warning "Detected automount path: $current_mount"
            print_info "Consider adding this partition to /etc/fstab for a stable mount point"
        fi
        echo "$current_mount"
    fi
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

    # Check if already mounted - prefer fstab location over automount
    local current_mount=$(get_preferred_mount "$partition")
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
        "arm"  # ARM temporary ripping storage
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
        print_info "Existing .env found - preserving values, adding missing variables"

        # Backup before making changes
        local backup_file=".env.backup.$(date +%Y%m%d_%H%M%S)"
        cp .env "$backup_file"
        print_success "Backup created: $backup_file"
        echo ""

        # Source existing values so we can use them
        set -a
        source .env
        set +a
    fi

    # --- System Configuration ---

    # Timezone - auto-detect from system
    local existing_tz=$(get_env_value "TZ")
    if [ -z "$existing_tz" ]; then
        TZ=$(detect_timezone)
        set_env_value "TZ" "$TZ"
        print_success "Auto-detected timezone: $TZ"
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

    # Note: Homepage dashboard doesn't require encryption keys
    # It uses file-based YAML configuration that's generated during setup

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

    # Show configuration summary
    echo ""
    print_success "Environment configuration complete"
    echo ""
    echo "  Timezone:     $TZ"
    echo "  User/Group:   $PUID:$PGID"
    echo "  Media root:   $MEDIA_ROOT"
    if [ -n "$DOMAIN" ]; then
        echo "  Domain:       $DOMAIN"
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
        "data/homepage/config"
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

    # Auto-detect optical drives
    local optical_drives=$(detect_optical_drives)

    if [ -z "$optical_drives" ]; then
        print_warning "No optical drives detected"
        print_info "Skipping ARM udev configuration"
        print_info "If you add an optical drive later, re-run this script"
        return
    fi

    # Display detected drives
    print_success "Detected optical drive(s):"
    for drive in $optical_drives; do
        local drive_info=$(get_optical_drive_info "$drive")
        local sg_device=$(find_sg_device "$drive")
        print_info "  $drive - $drive_info"
        if [ -n "$sg_device" ]; then
            print_info "    SCSI generic device: $sg_device"
        fi
    done

    # Store detected drives for docker-compose configuration
    DETECTED_OPTICAL_DRIVES="$optical_drives"
    DETECTED_OPTICAL_DRIVE=$(echo "$optical_drives" | awk '{print $1}')  # First drive
    DETECTED_SG_DEVICE=$(find_sg_device "$DETECTED_OPTICAL_DRIVE")

    # Save to .env for docker-compose to use
    set_env_value "OPTICAL_DRIVE" "${DETECTED_OPTICAL_DRIVE:-/dev/sr0}"
    set_env_value "OPTICAL_SG_DEVICE" "${DETECTED_SG_DEVICE:-/dev/sg1}"
    print_success "Optical drive configuration saved to .env"

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

# Setup scheduled maintenance cron jobs
setup_cron_jobs() {
    print_section "Setting Up Scheduled Maintenance"

    local cron_updated=false
    local current_cron=$(crontab -l 2>/dev/null || echo "")

    # Tdarr temp cleanup - remove orphaned transcode files older than 1 day
    local tdarr_cron="0 2 * * * find $(pwd)/data/tdarr/temp -mindepth 1 -mtime +1 -delete 2>/dev/null"

    if echo "$current_cron" | grep -q "tdarr/temp"; then
        print_info "Tdarr temp cleanup cron already exists"
    else
        print_info "Adding Tdarr temp cleanup cron (daily at 2am)..."
        (echo "$current_cron"; echo "$tdarr_cron") | crontab -
        cron_updated=true
        print_success "Tdarr temp cleanup scheduled: removes orphaned files older than 1 day"
    fi

    if [ "$cron_updated" = true ]; then
        print_success "Cron jobs configured"
    else
        print_info "All cron jobs already configured"
    fi
}

# Validate docker-compose.yml
# Detect and save hardware configuration
detect_hardware() {
    print_section "Hardware Auto-Detection"

    # GPU Detection
    local gpu_type=$(detect_gpu_type)
    local gpu_name=$(get_gpu_name "$gpu_type")
    print_success "GPU: $gpu_name"
    set_env_value "GPU_TYPE" "$gpu_type"

    # Optical Drive Detection (already done in setup_arm_udev, but show summary)
    local optical_drives=$(detect_optical_drives)
    if [ -n "$optical_drives" ]; then
        local drive_count=$(echo "$optical_drives" | wc -w)
        print_success "Optical drives: $drive_count detected"
        for drive in $optical_drives; do
            local info=$(get_optical_drive_info "$drive")
            print_info "  $drive - $info"
        done
    else
        print_info "Optical drives: None detected"
    fi

    # Memory Detection
    local total_mem=$(free -h | awk '/^Mem:/{print $2}')
    print_success "System memory: $total_mem"

    # CPU Detection
    local cpu_cores=$(nproc)
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    print_success "CPU: $cpu_model ($cpu_cores cores)"

    echo ""
    print_info "Hardware detection complete - configuration saved to .env"
}

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
        echo "  Homepage:       https://home.${domain}"
        echo "  Jellyfin:       https://jellyfin.${domain}"
        echo "  Jellyseerr:     https://jellyseerr.${domain}"
        echo ""
    fi

    echo -e "${BLUE}All Services (LAN: ${lan_ip}):${NC}"
    echo "  Homepage:       http://${lan_ip}:3000"
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
    detect_hardware
    create_compose_override
    create_directories
    setup_arm_udev
    setup_cron_jobs
    validate_compose
    pull_images
    start_services
    sleep 5  # Give services a moment to initialize
    show_status
    show_access_info

    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   ${GREEN}✓ SETUP COMPLETE${NC}                                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Your homelab is now running!"
    echo ""
    echo "  Useful commands:"
    echo "    docker compose logs -f       View logs"
    echo "    docker compose down          Stop services"
    echo "    docker compose up -d         Start services"
    echo "    docker compose pull          Update images"
    echo ""
}

# Run main function
main
