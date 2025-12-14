#!/bin/bash
#
# detect.cgi - Hardware detection API endpoint
# Returns hardware detection results as JSON
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

# Source library
source "$SCRIPT_DIR/../lib/init.sh"

# Run detection and output JSON
detect_all_hardware --json
