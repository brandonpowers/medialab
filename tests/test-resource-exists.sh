#!/bin/bash
#
# Unit tests for resource_exists_by_name (scripts/lib/api.sh).
# Mirrors how the *arr APIs return collections: a JSON array of objects each
# carrying a "name" field.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/api.sh"

list='[{"id":1,"name":"qBittorrent"},{"id":2,"name":"SABnzbd"}]'

resource_exists_by_name "$list" "qBittorrent"; assert_rc 0 $? "existing name matches"
resource_exists_by_name "$list" "SABnzbd";     assert_rc 0 $? "second existing name matches"
resource_exists_by_name "$list" "Deluge";      assert_rc 1 $? "absent name does not match"

# Name matching must be exact, not substring.
resource_exists_by_name "$list" "qBit";        assert_rc 1 $? "substring is not a match"

# Empty/whitespace API responses mean 'nothing exists yet' -> not found, no error.
resource_exists_by_name "[]" "qBittorrent";    assert_rc 1 $? "empty array -> not found"
resource_exists_by_name "" "qBittorrent";      assert_rc 1 $? "empty string -> not found"

# A malformed (non-JSON) response must not crash; treat as not found.
resource_exists_by_name "<html>500</html>" "qBittorrent"; assert_rc 1 $? "non-JSON -> not found, no crash"

finish_tests
