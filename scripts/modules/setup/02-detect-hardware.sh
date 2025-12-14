#!/bin/bash
#
# 02-detect-hardware.sh - Auto-detect hardware configuration
# Detects GPU, optical drives, CPU, memory, and system settings
#
# Usage:
#   ./02-detect-hardware.sh [--json]
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
    init_progress "Hardware Detection" 5

    local project_root
    project_root=$(get_project_root)

    # Step 1: Detect timezone
    report_progress 1 5 "Detecting timezone..."
    local timezone
    timezone=$(detect_timezone)
    report_progress 1 5 "Timezone: $timezone" "complete"

    # Step 2: Detect GPU
    report_progress 2 5 "Detecting GPU type..."
    local gpu_type gpu_name
    gpu_type=$(detect_gpu_type)
    gpu_name=$(get_gpu_name "$gpu_type")
    report_progress 2 5 "GPU: $gpu_name" "complete"

    # Step 3: Detect optical drives
    report_progress 3 5 "Detecting optical drives..."
    local optical_drives sg_device optical_count
    optical_drives=$(detect_optical_drives)

    if [[ -n "$optical_drives" ]]; then
        optical_count=$(echo "$optical_drives" | wc -w)
        local first_drive
        first_drive=$(echo "$optical_drives" | awk '{print $1}')
        sg_device=$(find_sg_device "$first_drive")

        report_progress 3 5 "Optical drives: $optical_count detected" "complete"

        # Log drive details
        for drive in $optical_drives; do
            local info
            info=$(get_optical_drive_info "$drive")
            report_log "info" "  $drive - $info"
        done
    else
        optical_count=0
        sg_device=""
        report_progress 3 5 "No optical drives detected" "complete"
    fi

    # Step 4: Detect system resources
    report_progress 4 5 "Detecting system resources..."
    local total_mem cpu_cores cpu_model
    total_mem=$(detect_memory)
    cpu_cores=$(detect_cpu_cores)
    cpu_model=$(detect_cpu_model)
    report_progress 4 5 "CPU: $cpu_cores cores, Memory: $total_mem" "complete"

    # Step 5: Save to .env
    report_progress 5 5 "Saving hardware configuration..."

    set_env_value "GPU_TYPE" "$gpu_type" "false" "$project_root/.env"
    set_env_value "TZ" "$timezone" "false" "$project_root/.env"

    if [[ -n "$optical_drives" ]]; then
        local first_drive
        first_drive=$(echo "$optical_drives" | awk '{print $1}')
        set_env_value "OPTICAL_DRIVE" "$first_drive" "false" "$project_root/.env"
        [[ -n "$sg_device" ]] && set_env_value "OPTICAL_SG_DEVICE" "$sg_device" "false" "$project_root/.env"
    fi

    report_progress 5 5 "Configuration saved" "complete"

    # Output JSON summary if requested
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        cat <<EOF
{
    "gpu": {"type": "$gpu_type", "name": "$gpu_name"},
    "optical": {"drives": "$optical_drives", "count": $optical_count, "sg_device": "$sg_device"},
    "system": {"memory": "$total_mem", "cpu_cores": $cpu_cores, "cpu_model": "$cpu_model"},
    "timezone": "$timezone"
}
EOF
    fi

    finish_progress "complete" "Hardware detection complete"
}

main "$@"
