#!/bin/bash
#
# Unit tests for json_first_id (scripts/lib/api.sh): extract the first "id"
# from an *arr API response, whether it is a single object or an array, with a
# caller-supplied fallback for empty/malformed input.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/api.sh"

# Single object (e.g. POST /tag response).
assert_eq "5" "$(json_first_id '{"id":5,"label":"flaresolverr"}')" "object -> its id"

# Array (e.g. GET /qualityprofile): first element's id.
assert_eq "3" "$(json_first_id '[{"id":3,"name":"HD"},{"id":4,"name":"4K"}]')" "array -> first id"

# Empty array -> default.
assert_eq "1" "$(json_first_id '[]' '1')" "empty array -> default"

# Missing id field -> default.
assert_eq "1" "$(json_first_id '{"label":"x"}' '1')" "missing id -> default"

# Empty / malformed input -> default, no crash.
assert_eq "1" "$(json_first_id '' '1')" "empty string -> default"
assert_eq "1" "$(json_first_id '<html>500</html>' '1')" "non-JSON -> default"

# No default supplied -> empty string.
assert_eq "" "$(json_first_id '[]')" "no default -> empty"

finish_tests
