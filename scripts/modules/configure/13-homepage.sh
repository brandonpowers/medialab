#!/bin/bash
#
# 13-homepage.sh - Verify Homepage dashboard is running
# Part of the configure phase
#
# Homepage is configured via YAML files generated during setup.
# This script just verifies the dashboard is accessible.
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Verify Homepage"
MODULE_STEP=13
MODULE_TOTAL=13

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Homepage Dashboard Verification"

    # Homepage configuration
    local homepage_host="${HOMEPAGE_HOST:-localhost}"
    local homepage_port="${HOMEPAGE_PORT:-3000}"
    local homepage_url="http://${homepage_host}:${homepage_port}"

    # Check if Homepage is running
    print_info "Checking Homepage availability at ${homepage_url}..."

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "${homepage_url}" > /dev/null 2>&1; then
            report_log "success" "Homepage is running and accessible"
            break
        fi

        if [[ $attempt -eq $max_attempts ]]; then
            report_log "error" "Homepage is not accessible at ${homepage_url}"
            print_info "Make sure Homepage is running: docker compose ps homepage"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "error"
            exit 1
        fi

        print_info "Waiting for Homepage... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    # Get server IP for display
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    # Verify config files exist
    local project_root
    project_root=$(get_project_root)
    local config_dir="$project_root/data/homepage/config"

    local config_files=("settings.yaml" "services.yaml" "docker.yaml" "widgets.yaml" "bookmarks.yaml")
    local missing=0

    for file in "${config_files[@]}"; do
        if [[ ! -f "$config_dir/$file" ]]; then
            report_log "warning" "Missing config file: $file"
            ((missing++))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        report_log "warning" "$missing config files missing - regenerate with 05b-generate-configs.sh"
    else
        report_log "success" "All configuration files present"
    fi

    # Summary
    print_section "Homepage Dashboard Ready!"

    echo ""
    print_info "Dashboard URL: http://${server_ip}:3000"
    echo ""
    echo "Features:"
    echo "  - Service widgets with live status"
    echo "  - Container health monitoring via Docker socket"
    echo "  - System resource monitoring"
    echo ""
    echo "Configuration files: $config_dir/"
    echo "  - settings.yaml  (theme, layout)"
    echo "  - services.yaml  (service widgets)"
    echo "  - docker.yaml    (container status)"
    echo "  - widgets.yaml   (info widgets)"
    echo "  - bookmarks.yaml (quick links)"
    echo ""
    print_info "Edit YAML files to customize your dashboard"

    report_log "success" "Homepage dashboard is ready!"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
