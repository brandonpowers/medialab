#!/bin/bash
#
# Behavior tests for ensure_resource (scripts/lib/api.sh). The HTTP boundaries
# api_get/api_post are the only seams stubbed; the branching logic under test
# is real.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/api.sh"

# Silence report_log during assertions.
report_log() { :; }

# --- Case 1: resource already exists -> skip, no POST, rc 0 ---------------
api_get()  { echo '[{"id":1,"name":"qBittorrent"}]'; }
api_post() { echo "POST-SHOULD-NOT-RUN" >&2; return 1; }
ensure_resource "qBittorrent" "http://x/downloadclient" "qBittorrent" '{}' "key"
assert_rc 0 $? "existing resource -> skip returns success"

# --- Case 2: resource absent, POST succeeds (echoes id) -> rc 0 -----------
api_get()  { echo '[]'; }
api_post() { echo '{"id":7,"name":"qBittorrent"}'; }
ensure_resource "qBittorrent" "http://x/downloadclient" "qBittorrent" '{}' "key"
assert_rc 0 $? "absent resource + good POST returns success"

# --- Case 3: resource absent, POST fails (no id in body) -> rc 1 ----------
api_get()  { echo '[]'; }
api_post() { echo '{"message":"Validation failed"}'; }
ensure_resource "qBittorrent" "http://x/downloadclient" "qBittorrent" '{}' "key"
assert_rc 1 $? "absent resource + rejected POST returns failure"

# --- Case 4: GET fails entirely (empty), POST succeeds -> rc 0 ------------
# A failed GET must not be mistaken for "exists"; we should still attempt POST.
api_get()  { return 1; }
api_post() { echo '{"id":9,"name":"qBittorrent"}'; }
ensure_resource "qBittorrent" "http://x/downloadclient" "qBittorrent" '{}' "key"
assert_rc 0 $? "failed GET still attempts create"

finish_tests
