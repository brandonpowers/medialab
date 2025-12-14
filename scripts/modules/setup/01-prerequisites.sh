#!/bin/bash
#
# 01-prerequisites.sh - Check and install prerequisites
# Verifies Docker, Docker Compose, and other dependencies are available
#
# Usage:
#   ./01-prerequisites.sh [--json]
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
    init_progress "Check Prerequisites" 4

    # Step 1: Check directory
    report_progress 1 4 "Checking working directory..."
    local project_root
    project_root=$(get_project_root)

    if [[ ! -f "$project_root/docker-compose.yml" ]]; then
        report_progress 1 4 "docker-compose.yml not found" "error"
        finish_progress "error" "Please run from the homelab directory"
        exit 1
    fi
    report_progress 1 4 "Working directory OK" "complete"

    # Step 2: Check Docker
    report_progress 2 4 "Checking Docker installation..."
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        report_progress 2 4 "Docker installed: $docker_version" "complete"

        # Configure Docker daemon even if already installed
        if [[ $EUID -eq 0 ]]; then
            configure_docker_daemon
        fi
    else
        report_progress 2 4 "Docker not found - installing..." "running"
        if [[ $EUID -ne 0 ]]; then
            report_progress 2 4 "Root required to install Docker" "error"
            finish_progress "error" "Run with sudo to install Docker"
            exit 1
        fi
        install_docker
        report_progress 2 4 "Docker installed" "complete"
    fi

    # Step 3: Check Docker Compose
    report_progress 3 4 "Checking Docker Compose..."
    if docker compose version &>/dev/null; then
        local compose_version
        compose_version=$(docker compose version 2>/dev/null || echo "unknown")
        report_progress 3 4 "Docker Compose: $compose_version" "complete"
    else
        report_progress 3 4 "Docker Compose not available" "error"
        finish_progress "error" "Docker Compose is required"
        exit 1
    fi

    # Step 4: Check OpenSSL
    report_progress 4 4 "Checking OpenSSL..."
    if command_exists openssl; then
        report_progress 4 4 "OpenSSL installed" "complete"
    else
        report_progress 4 4 "Installing OpenSSL..." "running"
        if [[ $EUID -eq 0 ]]; then
            apt-get install -y openssl &>/dev/null
            report_progress 4 4 "OpenSSL installed" "complete"
        else
            report_progress 4 4 "OpenSSL not found (install with apt)" "warning"
        fi
    fi

    finish_progress "complete" "All prerequisites satisfied"
}

main "$@"
