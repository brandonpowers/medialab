#!/bin/bash
#
# run-ui.sh - Start the web UI development server
# Serves the web wizard on http://localhost:8000
#
# Usage:
#   ./scripts/run-ui.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

URL="http://localhost:8000"

echo "Starting Medialab Setup Wizard..."
echo ""
echo "Opening browser to: $URL"
echo "Press Ctrl+C to stop"
echo ""

cd "$PROJECT_ROOT/web"

# Open browser after a short delay (give server time to start)
(sleep 1 && xdg-open "$URL" 2>/dev/null || open "$URL" 2>/dev/null || true) &

# Start Python HTTP server with CGI support
python3 -m http.server 8000 --cgi 2>/dev/null || \
    python -m http.server 8000 --cgi
