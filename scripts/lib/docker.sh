#!/bin/bash
#
# docker.sh - Docker operations with progress reporting
# Handles image pulling, container management, and compose operations
#

# Prevent multiple sourcing
[[ -n "${_HOMELAB_DOCKER_LOADED:-}" ]] && return 0
_HOMELAB_DOCKER_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/progress.sh"

# ============================================
# DOCKER CHECKS
# ============================================

# Check if Docker is installed and running
check_docker() {
    if ! command_exists docker; then
        print_error "Docker is not installed"
        return 1
    fi

    if ! docker info &>/dev/null; then
        print_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    if docker compose version &>/dev/null; then
        return 0
    fi

    if command_exists docker-compose; then
        print_warning "Using legacy docker-compose command"
        return 0
    fi

    print_error "Docker Compose is not available"
    return 1
}

# ============================================
# DOCKER INSTALLATION
# ============================================

# Install Docker (Ubuntu/Debian)
install_docker() {
    report_log "info" "Installing Docker..."

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
        report_log "success" "Docker installed successfully"

        # Start and enable Docker
        systemctl start docker
        systemctl enable docker &>/dev/null

        report_log "success" "Docker service started"
        return 0
    else
        report_log "error" "Failed to install Docker"
        return 1
    fi
}

# Configure Docker daemon settings
configure_docker_daemon() {
    report_log "info" "Configuring Docker daemon..."
    mkdir -p /etc/docker

    # Backup existing config
    if [[ -f /etc/docker/daemon.json ]]; then
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

    # Reload and restart Docker
    systemctl daemon-reload
    systemctl restart docker

    report_log "success" "Docker daemon configured"
}

# ============================================
# COMPOSE OPERATIONS
# ============================================

# Get list of services from docker-compose.yml
# Usage: get_compose_services [compose_file]
get_compose_services() {
    local compose_file="${1:-docker-compose.yml}"
    docker compose -f "$compose_file" config --services 2>/dev/null
}

# Get list of images from docker-compose.yml
# Usage: get_compose_images [compose_file]
get_compose_images() {
    local compose_file="${1:-docker-compose.yml}"
    docker compose -f "$compose_file" config --images 2>/dev/null
}

# Pull images with progress reporting
# Usage: pull_images_with_progress [compose_file]
pull_images_with_progress() {
    local compose_file="${1:-docker-compose.yml}"

    # Get total number of services
    local services
    services=$(get_compose_services "$compose_file")
    local total
    total=$(echo "$services" | wc -l)
    local current=0

    report_progress 0 "$total" "Starting image pull..."

    # Pull each service's image
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        ((current++))

        report_progress "$current" "$total" "Pulling $service..." "running"

        if docker compose -f "$compose_file" pull "$service" 2>&1 | while IFS= read -r line; do
            # Parse docker progress output for sub-progress
            if [[ "$line" =~ ([0-9]+)% ]]; then
                report_sub_progress "$service" "${BASH_REMATCH[1]}" ""
            fi
        done; then
            report_progress "$current" "$total" "Pulled $service" "complete"
        else
            report_progress "$current" "$total" "Failed to pull $service" "error"
        fi
    done <<< "$services"

    report_progress "$total" "$total" "All images pulled" "complete"
}

# Start services with progress reporting
# Usage: start_services_with_progress [compose_file]
start_services_with_progress() {
    local compose_file="${1:-docker-compose.yml}"

    local services
    services=$(get_compose_services "$compose_file")
    local total
    total=$(echo "$services" | wc -l)

    report_progress 0 "$total" "Starting containers..."

    # Start all services
    if docker compose -f "$compose_file" up -d 2>&1 | while IFS= read -r line; do
        # Parse container start messages
        if [[ "$line" =~ Container[[:space:]]+([^[:space:]]+)[[:space:]]+Started ]]; then
            local container="${BASH_REMATCH[1]}"
            report_log "success" "Started $container"
        elif [[ "$line" =~ Creating[[:space:]]+([^[:space:]]+) ]]; then
            local container="${BASH_REMATCH[1]}"
            report_log "info" "Creating $container"
        fi
    done; then
        report_progress "$total" "$total" "All containers started" "complete"
        return 0
    else
        report_progress "$total" "$total" "Some containers failed to start" "error"
        return 1
    fi
}

# Stop all services
# Usage: stop_services [compose_file]
stop_services() {
    local compose_file="${1:-docker-compose.yml}"

    report_log "info" "Stopping services..."
    docker compose -f "$compose_file" down

    report_log "success" "Services stopped"
}

# Get container status
# Usage: get_container_status [compose_file]
get_container_status() {
    local compose_file="${1:-docker-compose.yml}"
    docker compose -f "$compose_file" ps --format json 2>/dev/null || \
        docker compose -f "$compose_file" ps
}

# ============================================
# VALIDATION
# ============================================

# Validate docker-compose.yml syntax
# Usage: validate_compose [compose_file]
validate_compose() {
    local compose_file="${1:-docker-compose.yml}"

    if docker compose -f "$compose_file" config --quiet 2>&1 | grep -q "error"; then
        report_log "error" "docker-compose.yml validation failed"
        docker compose -f "$compose_file" config
        return 1
    fi

    report_log "success" "docker-compose.yml is valid"
    return 0
}

# ============================================
# CONTAINER LOGS
# ============================================

# Get temporary password from qBittorrent logs
get_qbittorrent_temp_password() {
    docker compose logs qbittorrent 2>/dev/null | \
        grep -oP 'temporary password is provided for this session: \K\S+' | \
        tail -1 || true
}

# Stream container logs
# Usage: stream_logs <service> [lines]
stream_logs() {
    local service="$1"
    local lines="${2:-100}"

    docker compose logs -f --tail "$lines" "$service"
}
