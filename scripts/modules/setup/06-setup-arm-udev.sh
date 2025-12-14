#!/bin/bash
#
# 06-setup-arm-udev.sh - Setup ARM automatic disc detection
# Configures udev rules for automatic Blu-ray/DVD ripping
#
# Usage:
#   ./06-setup-arm-udev.sh [--json]
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --json) OUTPUT_MODE="json" ;;
    esac
done

# ============================================
# MAIN
# ============================================

main() {
    init_progress "ARM Disc Detection Setup" 4
    local project_root
    project_root=$(get_project_root)

    # Step 1: Detect optical drives
    report_progress 1 4 "Detecting optical drives..."

    local optical_drives
    optical_drives=$(detect_optical_drives)

    if [[ -z "$optical_drives" ]]; then
        report_progress 1 4 "No optical drives detected" "skipped"
        finish_progress "complete" "ARM udev setup skipped (no optical drives)"

        if [[ "$OUTPUT_MODE" == "json" ]]; then
            echo "{\"status\": \"skipped\", \"reason\": \"no_optical_drives\"}"
        fi
        return
    fi

    # Display detected drives
    local drive_count=0
    for drive in $optical_drives; do
        ((drive_count++))
        local drive_info
        drive_info=$(get_optical_drive_info "$drive")
        local sg_device
        sg_device=$(find_sg_device "$drive")
        report_log "success" "Detected: $drive - $drive_info"
        [[ -n "$sg_device" ]] && report_log "info" "  SCSI generic: $sg_device"
    done

    report_progress 1 4 "$drive_count optical drive(s) detected" "complete"

    # Step 2: Save to .env
    report_progress 2 4 "Saving drive configuration..."

    local first_drive sg_device
    first_drive=$(echo "$optical_drives" | awk '{print $1}')
    sg_device=$(find_sg_device "$first_drive")

    set_env_value "OPTICAL_DRIVE" "$first_drive" "true" "$project_root/.env"
    set_env_value "OPTICAL_SG_DEVICE" "${sg_device:-/dev/sg1}" "true" "$project_root/.env"

    report_progress 2 4 "Configuration saved" "complete"

    # Step 3: Create udev wrapper script
    report_progress 3 4 "Creating ARM udev wrapper..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        report_progress 3 4 "Root required for udev setup" "skipped"
        report_log "warning" "Run with sudo to configure udev rules"
    else
        cat > /usr/local/bin/arm-udev-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
# ARM udev wrapper - passes udev environment variables to ARM container
# Called by udev when an optical disc is inserted

DEVNAME="$1"

# Export udev environment variables to the container
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
        report_log "success" "Wrapper script created at /usr/local/bin/arm-udev-wrapper.sh"

        report_progress 3 4 "Wrapper script created" "complete"
    fi

    # Step 4: Create udev rule
    report_progress 4 4 "Creating udev rule..."

    if [[ $EUID -eq 0 ]]; then
        # Create udev rule (single line)
        echo 'ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr[0-9]*", ENV{ID_CDROM_MEDIA}=="1", RUN+="/usr/local/bin/arm-udev-wrapper.sh %k"' \
            > /etc/udev/rules.d/99-arm.rules

        report_log "success" "Udev rule created at /etc/udev/rules.d/99-arm.rules"

        # Reload udev rules
        if udevadm control --reload-rules 2>/dev/null; then
            report_log "success" "Udev rules reloaded"
        else
            report_log "warning" "Could not reload udev rules - will be active after reboot"
        fi

        report_progress 4 4 "Udev rule configured" "complete"
    else
        report_progress 4 4 "Root required for udev rule" "skipped"
    fi

    finish_progress "complete" "ARM automatic disc detection configured"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        cat <<EOF
{
    "status": "configured",
    "drives": "$optical_drives",
    "drive_count": $drive_count,
    "primary_drive": "$first_drive",
    "sg_device": "$sg_device"
}
EOF
    else
        echo ""
        report_log "info" "Insert a disc to test auto-ripping"
        report_log "info" "Monitor with: docker logs -f arm"
    fi
}

main "$@"
