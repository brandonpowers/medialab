#!/bin/bash
#
# init.sh - Initialize all medialab library functions
# Source this file to get access to all shared functions
#
# Usage:
#   source /path/to/scripts/lib/init.sh
#   # Now all library functions are available
#

# Get the directory containing this script
_MEDIALAB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library modules
source "$_MEDIALAB_LIB_DIR/common.sh"
source "$_MEDIALAB_LIB_DIR/services.sh"
source "$_MEDIALAB_LIB_DIR/progress.sh"
source "$_MEDIALAB_LIB_DIR/detect.sh"
source "$_MEDIALAB_LIB_DIR/env.sh"
source "$_MEDIALAB_LIB_DIR/api.sh"
source "$_MEDIALAB_LIB_DIR/docker.sh"

# Export library directory for other scripts
export MEDIALAB_LIB_DIR="$_MEDIALAB_LIB_DIR"
