#!/bin/bash
#
# 03-select-media-drive.sh - Select and configure media storage drive
# Handles drive selection, formatting, and mounting
#
# Usage:
#   ./03-select-media-drive.sh [--json] [--device /dev/sdX] [--skip]
#
# Options:
#   --json           Output JSON format
#   --device PATH    Pre-select device (for non-interactive/UI mode)
#   --skip           Skip drive selection, use default /mnt/media
#   --format         Format the selected device (requires confirmation)
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Parse arguments
SELECTED_DEVICE=""
SKIP_SELECTION=false
DO_FORMAT=false
CONFIG_FILE=""
MEDIA_PATH=""

for arg in "$@"; do
    case $arg in
        --json) OUTPUT_MODE="json" ;;
        --skip) SKIP_SELECTION=true ;;
        --format) DO_FORMAT=true ;;
        --device=*) SELECTED_DEVICE="${arg#*=}" ;;
        --config=*) CONFIG_FILE="${arg#*=}" ;;
        --device)
            shift
            SELECTED_DEVICE="$1"
            ;;
        --config)
            shift
            CONFIG_FILE="$1"
            ;;
    esac
done

# Read from config file if provided
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    # Read storage config from JSON
    if command -v jq &>/dev/null; then
        cfg_device=$(jq -r '.storage.drive_device // empty' "$CONFIG_FILE" 2>/dev/null || true)
        cfg_path=$(jq -r '.storage.media_path // empty' "$CONFIG_FILE" 2>/dev/null || true)
        cfg_format=$(jq -r '.storage.format_drive // false' "$CONFIG_FILE" 2>/dev/null || true)

        [[ -n "$cfg_device" && "$cfg_device" != "null" ]] && SELECTED_DEVICE="$cfg_device"
        [[ -n "$cfg_path" && "$cfg_path" != "null" ]] && MEDIA_PATH="$cfg_path"
        [[ "$cfg_format" == "true" ]] && DO_FORMAT=true

        # If we have a media path but no device, skip device selection
        if [[ -n "$MEDIA_PATH" && -z "$SELECTED_DEVICE" ]]; then
            SKIP_SELECTION=true
        fi
    fi
fi

# ============================================
# DRIVE FUNCTIONS
# ============================================

# Get preferred mount point (fstab > automount)
get_preferred_mount() {
    local partition="$1"
    local uuid
    uuid=$(blkid -s UUID -o value "$partition" 2>/dev/null)

    # Check fstab first
    if [[ -n "$uuid" ]]; then
        local fstab_mount
        fstab_mount=$(grep -E "UUID=$uuid|$partition" /etc/fstab 2>/dev/null | awk '{print $2}' | head -1)
        if [[ -n "$fstab_mount" && "$fstab_mount" != "none" && "$fstab_mount" != "swap" ]]; then
            echo "$fstab_mount"
            return
        fi
    fi

    # Fall back to current mount
    findmnt -n -o TARGET "$partition" 2>/dev/null || true
}

# Create media directory structure
create_media_structure() {
    local media_path="$1"

    local media_dirs=(
        "movies"
        "tv"
        "music"
        "downloads/complete"
        "downloads/incomplete"
        "downloads/watch"
        "transcode"
        "arm"
    )

    for dir in "${media_dirs[@]}"; do
        mkdir -p "$media_path/$dir"
    done

    # Set ownership
    local puid pgid
    puid=$(get_env_value "PUID" || echo "1000")
    pgid=$(get_env_value "PGID" || echo "1000")
    chown -R "${puid}:${pgid}" "$media_path"

    # Set comprehensive ACLs on ALL media directories
    # This ensures files created by any process (ARM, Tdarr, etc.) are accessible by PUID/PGID
    if command -v setfacl &> /dev/null; then
        report_log "info" "Setting comprehensive ACLs for all media directories..."

        # Set ACLs on root media path and all subdirectories
        local acl_dirs=(
            "$media_path"
            "$media_path/movies"
            "$media_path/tv"
            "$media_path/music"
            "$media_path/downloads"
            "$media_path/downloads/complete"
            "$media_path/downloads/incomplete"
            "$media_path/downloads/watch"
            "$media_path/transcode"
            "$media_path/arm"
        )

        for dir in "${acl_dirs[@]}"; do
            if [ -d "$dir" ]; then
                # Set current ACLs (for existing files)
                setfacl -R -m "u:${puid}:rwx" "$dir" 2>/dev/null || true
                setfacl -R -m "g:${pgid}:rwx" "$dir" 2>/dev/null || true

                # Set default ACLs (for future files) - THIS IS KEY!
                setfacl -R -d -m "u:${puid}:rwx" "$dir" 2>/dev/null || true
                setfacl -R -d -m "g:${pgid}:rwx" "$dir" 2>/dev/null || true
                setfacl -R -d -m "mask::rwx" "$dir" 2>/dev/null || true
            fi
        done

        report_log "success" "Comprehensive ACLs configured on all media directories"
        report_log "info" "New files will automatically inherit correct permissions"
    else
        report_log "warning" "setfacl not found - install 'acl' package for automatic permission handling"
    fi
}

# Format drive with single ext4 partition
format_drive() {
    local device="$1"

    report_log "warning" "This will ERASE ALL DATA on $device!"

    if [[ "$OUTPUT_MODE" != "json" ]]; then
        echo -n "Type 'YES' to confirm: "
        read -r confirm
        if [[ "$confirm" != "YES" ]]; then
            report_log "info" "Format cancelled"
            return 1
        fi
    fi

    report_log "info" "Formatting $device..."

    # Unmount any mounted partitions
    for part in $(lsblk -n -o NAME "$device" | tail -n +2); do
        umount "/dev/$part" 2>/dev/null || true
    done

    # Create GPT partition table and single partition
    parted -s "$device" mklabel gpt
    parted -s "$device" mkpart primary ext4 0% 100%

    sleep 2

    # Determine partition name
    local partition="${device}1"
    if [[ "$device" == *"nvme"* ]]; then
        partition="${device}p1"
    fi

    # Format as ext4
    mkfs.ext4 -F -L "media" "$partition"

    report_log "success" "Drive formatted"
    echo "$partition"
}

# Mount partition and add to fstab
mount_partition() {
    local partition="$1"
    local mount_point="$2"

    mkdir -p "$mount_point"

    # Check if already mounted
    local current_mount
    current_mount=$(get_preferred_mount "$partition")
    if [[ -n "$current_mount" ]]; then
        report_log "info" "Partition already mounted at $current_mount"
        echo "$current_mount"
        return
    fi

    # Mount the partition
    mount "$partition" "$mount_point"

    # Add to fstab
    local uuid
    uuid=$(blkid -s UUID -o value "$partition")
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid $mount_point ext4 defaults,nofail 0 2" >> /etc/fstab
        report_log "success" "Added to /etc/fstab"
    fi

    echo "$mount_point"
}

# ============================================
# MAIN
# ============================================

main() {
    init_progress "Media Drive Selection" 3
    local project_root
    project_root=$(get_project_root)

    # Step 1: Scan for drives
    report_progress 1 3 "Scanning for available drives..."

    if [[ "$SKIP_SELECTION" == "true" ]]; then
        report_progress 1 3 "Skipping drive selection" "complete"
        # Use configured path or default
        local media_root="${MEDIA_PATH:-/mnt/media}"
        mkdir -p "$media_root"
        set_env_value "MEDIA_ROOT" "$media_root" "false" "$project_root/.env"
        create_media_structure "$media_root"
        report_progress 2 3 "Storage path set" "complete"
        report_progress 3 3 "Storage configured: $media_root" "complete"
        finish_progress "complete" "Using path: $media_root"

        if [[ "$OUTPUT_MODE" == "json" ]]; then
            echo "{\"media_root\": \"$media_root\", \"status\": \"configured\"}"
        fi
        return
    fi

    # Get drive information
    local drives_json
    drives_json=$(list_storage_drives)

    if [[ "$OUTPUT_MODE" == "json" && -z "$SELECTED_DEVICE" ]]; then
        # Return drive list for UI selection
        local largest
        largest=$(detect_largest_storage_drive)
        echo "{\"drives\": $drives_json, \"recommended\": \"$largest\"}"
        return
    fi

    report_progress 1 3 "Drives scanned" "complete"

    # Step 2: Select drive
    report_progress 2 3 "Selecting media drive..."

    local selected_drive selected_mount

    if [[ -n "$SELECTED_DEVICE" ]]; then
        # Use pre-selected device
        selected_drive="$SELECTED_DEVICE"
        report_log "info" "Using device: $selected_drive"
    else
        # Interactive selection
        local drives=()
        local drive_info=()
        local largest_size=0
        local recommended_idx=-1

        while IFS= read -r line; do
            local name size size_bytes model mountpoint
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $2}')
            size_bytes=$(lsblk -d -b -n -o SIZE "/dev/$name" 2>/dev/null)
            model=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | xargs)
            mountpoint=$(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v "^$" | head -1)

            # Skip root drive
            [[ "$mountpoint" == "/" ]] && continue

            drives+=("$name")
            drive_info+=("$size|$model|$mountpoint")

            if [[ -n "$size_bytes" && "$size_bytes" -gt "$largest_size" ]]; then
                largest_size=$size_bytes
                recommended_idx=$((${#drives[@]} - 1))
            fi
        done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n | grep -E "^(sd|nvme|vd)" | grep -v "loop")

        if [[ ${#drives[@]} -eq 0 ]]; then
            report_log "warning" "No additional drives found"
            selected_mount="/mnt/media"
        else
            echo ""
            echo "Available drives:"
            printf "  %-4s %-12s %-10s %-20s %s\n" "#" "DEVICE" "SIZE" "MODEL" "MOUNT"
            echo "  ────────────────────────────────────────────────────────────────"

            for idx in "${!drives[@]}"; do
                local name="${drives[$idx]}"
                IFS='|' read -r size model mountpoint <<< "${drive_info[$idx]}"
                local rec=""
                [[ "$idx" -eq "$recommended_idx" ]] && rec=" (Recommended)"
                printf "  %-4s %-12s %-10s %-20s %s%s\n" "[$((idx+1))]" "/dev/$name" "$size" "${model:-Unknown}" "${mountpoint:-(not mounted)}" "$rec"
            done

            echo ""
            printf "  %-4s %s\n" "[S]" "Skip - use default /mnt/media"
            echo ""

            local selection
            read -r -p "Select drive [${recommended_idx+$((recommended_idx+1))}]: " selection

            if [[ -z "$selection" && "$recommended_idx" -ge 0 ]]; then
                selection=$((recommended_idx + 1))
            fi

            if [[ "$selection" =~ ^[Ss]$ ]]; then
                selected_mount="/mnt/media"
            elif [[ "$selection" =~ ^[0-9]+$ && "$selection" -ge 1 && "$selection" -le "${#drives[@]}" ]]; then
                selected_drive="/dev/${drives[$((selection-1))]}"
            else
                report_log "error" "Invalid selection"
                selected_mount="/mnt/media"
            fi
        fi
    fi

    report_progress 2 3 "Drive selected" "complete"

    # Step 3: Configure drive
    report_progress 3 3 "Configuring storage..."

    local media_root="/mnt/media"

    if [[ -n "${selected_drive:-}" ]]; then
        # Check for existing partitions
        local partitions
        partitions=$(lsblk -n -o NAME "$selected_drive" | tail -n +2 | head -1)

        if [[ -n "$partitions" ]]; then
            local partition="/dev/$partitions"
            local current_mount
            current_mount=$(get_preferred_mount "$partition")

            if [[ -n "$current_mount" ]]; then
                media_root="$current_mount"
                report_log "info" "Using existing mount: $media_root"
            elif [[ "$DO_FORMAT" == "true" ]]; then
                partition=$(format_drive "$selected_drive")
                media_root=$(mount_partition "$partition" "/mnt/media")
            else
                media_root=$(mount_partition "$partition" "/mnt/media")
            fi
        elif [[ "$DO_FORMAT" == "true" ]]; then
            local partition
            partition=$(format_drive "$selected_drive")
            media_root=$(mount_partition "$partition" "/mnt/media")
        else
            report_log "warning" "Drive has no partitions. Use --format to create one."
            media_root="/mnt/media"
        fi
    fi

    # Ensure media root exists
    mkdir -p "$media_root"

    # Save to .env
    set_env_value "MEDIA_ROOT" "$media_root" "false" "$project_root/.env"

    # Create directory structure
    create_media_structure "$media_root"

    report_progress 3 3 "Storage configured: $media_root" "complete"

    finish_progress "complete" "Media storage ready at $media_root"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        echo "{\"media_root\": \"$media_root\", \"status\": \"configured\"}"
    fi
}

main "$@"
