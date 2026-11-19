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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PROJECT_ROOT

URL="http://localhost:8000"

# The wizard's backend is CGI served by `http.server --cgi`, which Python
# removed in 3.15. Fail clearly rather than with a buried argparse error.
if ! command -v python3 > /dev/null 2>&1; then
    echo "[✗] python3 not found. Install it, or run the wizard container instead:"
    echo "        docker compose -f docker-compose.web.yml up -d"
    exit 1
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info < (3, 15) else 1)'; then
    echo "[✗] The setup wizard needs Python 3.14 or older (http.server --cgi was"
    echo "    removed in 3.15); this host has $(python3 --version 2>&1)."
    echo "    Run the wizard container instead (it pins python:3.14-slim):"
    echo "        docker compose -f docker-compose.web.yml up -d"
    exit 1
fi

echo "Starting Medialab Setup Wizard..."
echo ""
echo "Opening browser to: $URL"
echo "Press Ctrl+C to stop"
echo ""

cd "$PROJECT_ROOT/web"

# Open browser after a short delay (give server time to start)
(sleep 1 && xdg-open "$URL" 2>/dev/null || open "$URL" 2>/dev/null || true) &

# Start Python HTTP server with CGI support. 3.13/3.14 warn that --cgi is
# deprecated; that's expected (see the version check above).
exec python3 -W ignore::DeprecationWarning -m http.server 8000 --cgi
