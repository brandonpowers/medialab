#!/bin/bash
#
# detect.cgi - Hardware detection API endpoint
# Returns hardware detection results as JSON
#

# Determine PROJECT_ROOT / SCRIPT_DIR (CGI may not inherit env vars)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Shared CGI helpers (CSRF guard). Reject untrusted requests before any output.
source "$SCRIPT_DIR/cgi-common.sh"
cgi_guard

# Set content type
echo "Content-Type: application/json"
echo ""

# Source library
source "$PROJECT_ROOT/scripts/lib/init.sh"

# Run detection and output JSON
detect_all_hardware --json
