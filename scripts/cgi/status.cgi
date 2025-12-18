#!/bin/bash
#
# status.cgi - Service status API endpoint
# Returns Docker container status as JSON
#
# Query parameters:
#   check_pid=<pid>  - Check if a specific process is running
#

# Set content type
echo "Content-Type: application/json"
echo ""

# Get script directory (resolve symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library
source "$SCRIPT_DIR/../lib/init.sh"

# Parse query string for check_pid and kill_pid
check_pid=""
kill_pid=""
if [[ -n "$QUERY_STRING" ]]; then
    check_pid=$(echo "$QUERY_STRING" | grep -oP 'check_pid=\K\d+' || true)
    kill_pid=$(echo "$QUERY_STRING" | grep -oP 'kill_pid=\K\d+' || true)
fi

# If kill_pid is requested, kill that process
if [[ -n "$kill_pid" ]]; then
    if kill -0 "$kill_pid" 2>/dev/null; then
        # Kill the process and its children
        pkill -P "$kill_pid" 2>/dev/null || true
        kill "$kill_pid" 2>/dev/null || true
        sleep 0.5
        if kill -0 "$kill_pid" 2>/dev/null; then
            kill -9 "$kill_pid" 2>/dev/null || true
        fi
        echo '{"killed": true, "pid": '"$kill_pid"'}'
    else
        echo '{"killed": false, "pid": '"$kill_pid"', "message": "Process not found"}'
    fi
    exit 0
fi

# If check_pid is requested, just check that process
if [[ -n "$check_pid" ]]; then
    if kill -0 "$check_pid" 2>/dev/null; then
        echo '{"running": true, "pid": '"$check_pid"'}'
    else
        echo '{"running": false, "pid": '"$check_pid"'}'
    fi
    exit 0
fi

cd "$PROJECT_ROOT"

# Check if Docker is running
if ! docker info &>/dev/null; then
    echo '{"status": "error", "message": "Docker is not running"}'
    exit 0
fi

# Get container status (docker compose outputs one JSON per line, convert to array)
containers=$(docker compose ps --format json 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")

# Get service health
services=()
declare -A health_urls=(
    ["jellyfin"]="http://localhost:8096/health"
    ["sonarr"]="http://localhost:8989/ping"
    ["radarr"]="http://localhost:7878/ping"
    ["prowlarr"]="http://localhost:9696/ping"
    ["qbittorrent"]="http://localhost:8080"
    ["homepage"]="http://localhost:3000"
)

health_json="{"
first=true

for service in "${!health_urls[@]}"; do
    $first || health_json+=","
    first=false

    if curl -sf --max-time 2 "${health_urls[$service]}" &>/dev/null; then
        health_json+="\"$service\":\"healthy\""
    else
        health_json+="\"$service\":\"unhealthy\""
    fi
done

health_json+="}"

# Get LAN IP
lan_ip=$(hostname -I | awk '{print $1}')

# Output JSON
cat << EOF
{
    "status": "success",
    "lan_ip": "$lan_ip",
    "containers": $containers,
    "health": $health_json
}
EOF
