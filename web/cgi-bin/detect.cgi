#!/bin/bash
#
# detect.cgi - Hardware detection API endpoint
# Returns hardware detection results as JSON
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

# Run detection and output JSON
detect_all_hardware --json
