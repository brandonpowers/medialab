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

# Determine PROJECT_ROOT / SCRIPT_DIR (CGI may not inherit env vars)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Shared CGI helpers (CSRF guard, PID registry). Reject untrusted requests
# BEFORE emitting any headers or doing any work.
source "$SCRIPT_DIR/cgi-common.sh"
cgi_guard

# Set content type
echo "Content-Type: application/json"
echo ""

# Source library
source "$PROJECT_ROOT/scripts/lib/init.sh"

# Parse only the parameters we expect, with a strict character class. We do NOT
# assign arbitrary query-string keys to shell variables (the previous
# `printf -v "$key"` approach let a caller clobber PROJECT_ROOT, PATH, etc.).
phase=""
module=""
if [[ -n "${QUERY_STRING:-}" ]]; then
    phase=$(echo "$QUERY_STRING"  | grep -oP '(^|&)phase=\K[a-z]+'            | head -n1 || true)
    module=$(echo "$QUERY_STRING" | grep -oP '(^|&)module=\K[A-Za-z0-9._-]+'  | head -n1 || true)
fi

if [[ -z "$phase" || -z "$module" ]]; then
    echo '{"status": "error", "message": "Missing phase or module parameter"}'
    exit 0
fi

# Resolve the module directory for the requested phase.
case "$phase" in
    setup)     module_dir="$PROJECT_ROOT/scripts/modules/setup" ;;
    configure) module_dir="$PROJECT_ROOT/scripts/modules/configure" ;;
    *)
        echo '{"status": "error", "message": "Invalid phase"}'
        exit 0
        ;;
esac

# Validate `module` against the actual module files on disk (an allowlist that
# maintains itself). This rejects path traversal and any name that is not a
# real, top-level module in the requested phase.
module_path=""
if [[ "$module" != *"/"* && "$module" != *".."* && -f "$module_dir/${module}.sh" ]]; then
    module_path="$module_dir/${module}.sh"
fi

if [[ -z "$module_path" ]]; then
    echo "{\"status\": \"error\", \"message\": \"Unknown module: $module\"}"
    exit 0
fi

# Read POST body if present (config JSON)
CONFIG_FILE=""
if [[ "${REQUEST_METHOD:-}" == "POST" && -n "${CONTENT_LENGTH:-}" && "$CONTENT_LENGTH" -gt 0 ]]; then
    CONFIG_FILE="/tmp/medialab-config-$$.json"
    head -c "$CONTENT_LENGTH" > "$CONFIG_FILE"
fi

# Create progress file
progress_file="${MEDIALAB_PROGRESS_PREFIX}$$"
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

# Record this PID so status.cgi may later stop it (and only it).
wizard_register_pid "$pid"

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
