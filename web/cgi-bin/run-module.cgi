#!/bin/bash
#
# run-module.cgi - Execute a module with progress tracking
# Runs a setup/configure module and streams progress to a file
#
# Query parameters:
#   phase=setup|configure
#   module=01-prerequisites|02-detect-hardware|...
#
# POST body (optional):
#   JSON config object that will be saved and passed to modules
#

# Set content type
echo "Content-Type: application/json"
echo ""

# Determine PROJECT_ROOT if not set (CGI may not inherit env vars)
if [[ -z "$PROJECT_ROOT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Source library
source "$PROJECT_ROOT/scripts/lib/init.sh"

# Parse query string
parse_query() {
    local query="$QUERY_STRING"
    local key value

    while IFS='=' read -r -d '&' key value; do
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | sed 's/+/ /g; s/%/\\x/g')
        value=$(echo "$value" | sed 's/+/ /g; s/%/\\x/g')
        printf -v "$key" '%b' "$value"
    done <<< "${query}&"
}

parse_query

# Read POST body if present (config JSON)
CONFIG_FILE=""
if [[ "${REQUEST_METHOD:-}" == "POST" && -n "${CONTENT_LENGTH:-}" && "$CONTENT_LENGTH" -gt 0 ]]; then
    CONFIG_FILE="/tmp/medialab-config-$$.json"
    head -c "$CONTENT_LENGTH" > "$CONFIG_FILE"
fi

# Validate parameters
phase="${phase:-}"
module="${module:-}"

if [[ -z "$phase" || -z "$module" ]]; then
    echo '{"status": "error", "message": "Missing phase or module parameter"}'
    exit 0
fi

# Determine module path
case "$phase" in
    setup)
        module_path="$PROJECT_ROOT/scripts/modules/setup/${module}.sh"
        ;;
    configure)
        module_path="$PROJECT_ROOT/scripts/modules/configure/${module}.sh"
        ;;
    *)
        echo '{"status": "error", "message": "Invalid phase"}'
        exit 0
        ;;
esac

if [[ ! -f "$module_path" ]]; then
    echo "{\"status\": \"error\", \"message\": \"Module not found: $module\"}"
    exit 0
fi

# Create progress file
progress_file="/tmp/medialab-progress-$$"
touch "$progress_file"

# Run module in background with progress output
cd "$PROJECT_ROOT"
export OUTPUT_MODE="json"
export PROGRESS_FILE="$progress_file"

# Build module arguments
module_args="--json"
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    module_args="$module_args --config=$CONFIG_FILE"
fi

# Start module
bash "$module_path" $module_args > "$progress_file.out" 2>&1 &
pid=$!

# Return progress file info
cat << EOF
{
    "status": "started",
    "pid": $pid,
    "progress_file": "$progress_file",
    "output_file": "$progress_file.out",
    "phase": "$phase",
    "module": "$module"
}
EOF
