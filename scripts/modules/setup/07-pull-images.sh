#!/bin/bash
#
# 07-pull-images.sh - Pull all Docker images
# Downloads container images with progress reporting
#
# Usage:
#   ./07-pull-images.sh [--json]
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
    init_progress "Pull Docker Images" 3
    local project_root
    project_root=$(get_project_root)

    cd "$project_root"

    # Step 1: Validate compose file
    report_progress 1 3 "Validating docker-compose.yml..."

    if ! validate_compose; then
        finish_progress "error" "docker-compose.yml validation failed"
        exit 1
    fi

    report_progress 1 3 "Compose file valid" "complete"

    # Step 2: Count images
    report_progress 2 3 "Counting images to pull..."

    local services
    services=$(get_compose_services)
    local total
    total=$(echo "$services" | wc -l)

    report_log "info" "Found $total services to pull"
    report_progress 2 3 "$total images to pull" "complete"

    # Step 3: Pull images
    report_progress 3 3 "Pulling images..."

    # Set longer timeout for slow connections
    export COMPOSE_HTTP_TIMEOUT=120

    local current=0
    local failed=0

    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        ((current++))

        if [[ "$OUTPUT_MODE" == "json" ]]; then
            echo "{\"type\":\"pull\",\"service\":\"$service\",\"current\":$current,\"total\":$total}"
        else
            echo -ne "\r${BLUE}[$current/$total]${NC} Pulling $service...                    "
        fi

        if docker compose pull "$service" &>/dev/null; then
            report_log "success" "Pulled $service"
        else
            report_log "warning" "Failed to pull $service"
            ((failed++))
        fi
    done <<< "$services"

    [[ "$OUTPUT_MODE" != "json" ]] && echo ""

    if [[ $failed -gt 0 ]]; then
        report_progress 3 3 "Pulled images ($failed failed)" "warning"

        if [[ "$OUTPUT_MODE" != "json" ]]; then
            echo ""
            read -r -p "Continue anyway? (y/N): " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                finish_progress "error" "Pull cancelled"
                exit 1
            fi
        fi
    else
        report_progress 3 3 "All images pulled" "complete"
    fi

    finish_progress "complete" "Docker images ready"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        echo "{\"status\":\"complete\",\"total\":$total,\"failed\":$failed}"
    fi
}

main "$@"
