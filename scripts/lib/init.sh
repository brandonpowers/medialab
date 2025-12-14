#!/bin/bash
#
# init.sh - Initialize all homelab library functions
# Source this file to get access to all shared functions
#
# Usage:
#   source /path/to/scripts/lib/init.sh
#   # Now all library functions are available
#

# Get the directory containing this script
_HOMELAB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
source "$_HOMELAB_LIB_DIR/common.sh"
source "$_HOMELAB_LIB_DIR/progress.sh"
source "$_HOMELAB_LIB_DIR/detect.sh"
source "$_HOMELAB_LIB_DIR/env.sh"
source "$_HOMELAB_LIB_DIR/api.sh"
source "$_HOMELAB_LIB_DIR/docker.sh"

# Export library directory for other scripts
export HOMELAB_LIB_DIR="$_HOMELAB_LIB_DIR"
