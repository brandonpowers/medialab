#!/bin/bash
#
# detect.sh - Hardware detection functions
# Auto-detects GPU, optical drives, storage, and system configuration
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_DETECT_LOADED:-}" ]] && return 0
_MEDIALAB_DETECT_LOADED=1

# Source common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================
# TIMEZONE DETECTION
# ============================================

# Auto-detect system timezone
# Returns: timezone string (e.g., "America/New_York")
detect_timezone() {
    local tz=""

    # Method 1: timedatectl (systemd)
    if command_exists timedatectl; then
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
    fi

    # Method 2: /etc/timezone file
    if [[ -z "$tz" ]] && [[ -f /etc/timezone ]]; then
        tz=$(cat /etc/timezone 2>/dev/null | tr -d '[:space:]')
    fi

    # Method 3: /etc/localtime symlink
    if [[ -z "$tz" ]] && [[ -L /etc/localtime ]]; then
        tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    fi

    # Fallback
    echo "${tz:-America/Chicago}"
}

# ============================================
# GPU DETECTION
# ============================================

# Auto-detect GPU type for hardware transcoding
# Returns: vaapi, nvenc, qsv, or cpu
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
# Usage: get_gpu_name <gpu_type>
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

# Get GPU model from lspci
# Extracts model name from brackets if available, otherwise returns empty
get_gpu_model() {
    local gpu_info model_name
    gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1)

    if [[ -z "$gpu_info" ]]; then
        echo ""
        return
    fi

    # Extract the last bracketed item (usually the model name)
    # e.g., "[Radeon 880M / 890M]" or "[GeForce RTX 3080]"
    model_name=$(echo "$gpu_info" | grep -oE '\[[^]]+\]' | tail -1 | tr -d '[]')

    # Skip vendor-only brackets like [AMD/ATI] or [Intel]
    case "$model_name" in
        AMD/ATI|Intel|NVIDIA) model_name="" ;;
    esac

    # Take first model if multiple listed (e.g., "Radeon 880M / 890M" -> "Radeon 880M")
    echo "$model_name" | sed 's/ \/ .*//'
}

# ============================================
# OPTICAL DRIVE DETECTION
# ============================================

# Auto-detect optical drives (Blu-ray/DVD/CD)
# Returns: space-separated list of device paths (e.g., "/dev/sr0 /dev/sr1")
detect_optical_drives() {
    local drives=()

    # Scan for sr* devices (optical drives)
    for dev in /dev/sr*; do
        if [[ -e "$dev" ]]; then
            drives+=("$dev")
        fi
    done

    echo "${drives[*]}"
}

# Get optical drive info (for display)
# Usage: get_optical_drive_info <device>
get_optical_drive_info() {
    local device="$1"
    local info=""

    # Try to get device model from udevadm
    if command_exists udevadm; then
        info=$(udevadm info --query=property --name="$device" 2>/dev/null | \
            grep -E "ID_MODEL=|ID_VENDOR=" | head -2 | cut -d'=' -f2 | tr '\n' ' ')
    fi

    # Fallback: check sysfs
    if [[ -z "$info" ]]; then
        local basename
        basename=$(basename "$device")
        if [[ -e "/sys/class/block/${basename}/device/model" ]]; then
            info=$(cat "/sys/class/block/${basename}/device/model" 2>/dev/null)
        fi
    fi

    echo "${info:-Unknown optical drive}"
}

# Find the corresponding SCSI generic device for an optical drive
# Usage: find_sg_device <sr_device>
find_sg_device() {
    local sr_device="$1"
    local sr_name
    sr_name=$(basename "$sr_device")

    # Method 1: Check sysfs for the sg device
    if [[ -d "/sys/class/block/$sr_name/device/scsi_generic" ]]; then
        local sg_name
        sg_name=$(ls "/sys/class/block/$sr_name/device/scsi_generic" 2>/dev/null | head -1)
        if [[ -n "$sg_name" ]]; then
            echo "/dev/$sg_name"
            return
        fi
    fi

    # Method 2: Find sg device with matching SCSI address
    local scsi_host
    scsi_host=$(readlink -f "/sys/class/block/$sr_name/device" 2>/dev/null | \
        grep -oP '\d+:\d+:\d+:\d+' | head -1)
    if [[ -n "$scsi_host" ]]; then
        for sg in /sys/class/scsi_generic/sg*; do
            local sg_scsi
            sg_scsi=$(readlink -f "$sg/device" 2>/dev/null | \
                grep -oP '\d+:\d+:\d+:\d+' | head -1)
            if [[ "$sg_scsi" == "$scsi_host" ]]; then
                echo "/dev/$(basename "$sg")"
                return
            fi
        done
    fi

    # Fallback: assume sg device number matches sr device number
    local num
    num=$(echo "$sr_name" | grep -oP '\d+$')
    if [[ -e "/dev/sg$((num+1))" ]]; then
        echo "/dev/sg$((num+1))"
    fi
}

# ============================================
# STORAGE DETECTION
# ============================================

# Check if a drive contains system partitions (/, /boot, /home, swap, etc.)
# Usage: is_system_drive <device>
# Returns: 0 if system drive, 1 if not
is_system_drive() {
    local device="$1"
    local name
    name=$(basename "$device")

    # Get all mountpoints for this device and its partitions
    local mounts
    mounts=$(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v "^$" || true)

    # Check for system-critical mountpoints
    if echo "$mounts" | grep -qE "^/$|^/boot|^/home|^/var|^/usr|^\[SWAP\]$"; then
        return 0  # Is a system drive
    fi

    return 1  # Not a system drive
}

# Auto-detect the largest non-system storage drive
# Returns: device path (e.g., "/dev/sdb") or empty if none found
detect_largest_storage_drive() {
    local largest_drive=""
    local largest_size=0

    while IFS= read -r line; do
        local name size_bytes
        name=$(echo "$line" | awk '{print $1}')
        size_bytes=$(echo "$line" | awk '{print $2}')

        # Skip if size is empty or zero
        [[ -z "$size_bytes" || "$size_bytes" == "0" ]] && continue

        # Skip system drives (checks all partitions for system mounts)
        if is_system_drive "/dev/$name"; then
            continue
        fi

        # Check if this is larger than current largest
        if [[ "$size_bytes" -gt "$largest_size" ]]; then
            largest_size=$size_bytes
            largest_drive="/dev/$name"
        fi
    done < <(lsblk -d -b -n -o NAME,SIZE 2>/dev/null | grep -E "^(sd|nvme|vd)")

    echo "$largest_drive"
}

# Format bytes to human readable
# Usage: format_bytes <bytes>
format_bytes() {
    local bytes=$1
    if [[ "$bytes" -ge 1099511627776 ]]; then
        awk "BEGIN {printf \"%.1fTB\", $bytes/1099511627776}"
    elif [[ "$bytes" -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.1fGB\", $bytes/1073741824}"
    else
        awk "BEGIN {printf \"%.1fMB\", $bytes/1048576}"
    fi
}

# List all available storage drives with metadata (excludes system drives)
# Output format: JSON array of drive objects
list_storage_drives() {
    local json="["
    local first=true

    while IFS= read -r line; do
        local name size type model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | xargs)

        # Skip system drives (checks all partitions for system mounts)
        if is_system_drive "/dev/$name"; then
            continue
        fi

        local size_bytes mountpoint
        size_bytes=$(lsblk -d -b -n -o SIZE "/dev/$name" 2>/dev/null || echo "0")
        mountpoint=$(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v "^$" | head -1 || echo "")

        $first || json+=","
        first=false

        json+="{\"device\":\"/dev/$name\",\"size\":\"$size\",\"size_bytes\":${size_bytes:-0},\"model\":\"${model:-Unknown}\",\"mountpoint\":\"${mountpoint:-}\",\"is_system\":false}"
    done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n | grep -E "^(sd|nvme|vd)" | grep -v "loop")

    json+="]"
    echo "$json"
}

# List ALL drives with metadata (including system drives, marked appropriately)
# Output format: JSON array of drive objects
list_all_drives() {
    local json="["
    local first=true

    while IFS= read -r line; do
        local name size type model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | xargs)

        local size_bytes mountpoint is_system
        size_bytes=$(lsblk -d -b -n -o SIZE "/dev/$name" 2>/dev/null || echo "0")

        # Get all mountpoints for display
        mountpoint=$(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v "^$" | head -1 || echo "")

        # Check if system drive
        if is_system_drive "/dev/$name"; then
            is_system="true"
        else
            is_system="false"
        fi

        $first || json+=","
        first=false

        json+="{\"device\":\"/dev/$name\",\"size\":\"$size\",\"size_bytes\":${size_bytes:-0},\"model\":\"${model:-Unknown}\",\"mountpoint\":\"${mountpoint:-}\",\"is_system\":$is_system}"
    done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n | grep -E "^(sd|nvme|vd)" | grep -v "loop")

    json+="]"
    echo "$json"
}

# ============================================
# SYSTEM DETECTION
# ============================================

# Get system memory
detect_memory() {
    # Get memory in bytes and convert to human-readable format
    local mem_kb mem_gb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_gb=$(awk "BEGIN {printf \"%.0f\", $mem_kb / 1024 / 1024}")
    echo "${mem_gb} GB"
}

# Get CPU core count
detect_cpu_cores() {
    nproc
}

# Get CPU model
detect_cpu_model() {
    local model
    model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    # Remove integrated GPU references (e.g., "w/ Radeon 880M")
    model=$(echo "$model" | sed 's/ w\/.*$//')
    echo "$model"
}

# Get system hostname
detect_hostname() {
    hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "localhost"
}

# ============================================
# COMBINED HARDWARE DETECTION
# ============================================

# Detect all hardware and return as JSON
# Usage: detect_all_hardware [--json]
detect_all_hardware() {
    local gpu_type gpu_model optical_drives sg_device total_mem cpu_cores cpu_model

    gpu_type=$(detect_gpu_type)
    gpu_model=$(get_gpu_model)
    optical_drives=$(detect_optical_drives)
    total_mem=$(detect_memory)
    cpu_cores=$(detect_cpu_cores)
    cpu_model=$(detect_cpu_model)

    # Get SG device for first optical drive
    sg_device=""
    if [[ -n "$optical_drives" ]]; then
        local first_drive
        first_drive=$(echo "$optical_drives" | awk '{print $1}')
        sg_device=$(find_sg_device "$first_drive")
    fi

    if [[ "${1:-}" == "--json" ]]; then
        cat <<EOF
{
    "gpu": {
        "type": "$gpu_type",
        "name": "$(get_gpu_name "$gpu_type")",
        "model": "$gpu_model"
    },
    "optical": {
        "drives": "$optical_drives",
        "sg_device": "$sg_device"
    },
    "system": {
        "memory": "$total_mem",
        "cpu_cores": $cpu_cores,
        "cpu_model": "$cpu_model",
        "hostname": "$(detect_hostname)"
    },
    "timezone": "$(detect_timezone)"
}
EOF
    else
        echo "GPU: $(get_gpu_name "$gpu_type")"
        [[ -n "$gpu_model" ]] && echo "     $gpu_model"
        [[ -n "$optical_drives" ]] && echo "Optical: $optical_drives"
        echo "Memory: $total_mem"
        echo "CPU: $cpu_model ($cpu_cores cores)"
        echo "Timezone: $(detect_timezone)"
    fi
}
