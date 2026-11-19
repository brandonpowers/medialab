#!/bin/bash
#
# Unit tests for yaml_set_section_value (scripts/lib/common.sh), run against a
# config.yaml written by a fresh Bazarr 1.6.2 (API key zeroed).
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ORIG="$DIR/fixtures/bazarr-1.6.2-config.yaml"
cp "$ORIG" "$TMP/config.yaml"
CFG="$TMP/config.yaml"

# --- the exact edits 07-bazarr.sh makes ---------------------------------------
yaml_set_section_value "$CFG" auth type form raw;               assert_rc 0 $? "auth.type set"
yaml_set_section_value "$CFG" auth username "mladmin";           assert_rc 0 $? "auth.username set"
yaml_set_section_value "$CFG" auth password "5f4dcc3b5aa765d61d8327deb882cf99"; assert_rc 0 $? "auth.password set"
yaml_set_section_value "$CFG" general use_sonarr true raw;       assert_rc 0 $? "general.use_sonarr set"
yaml_set_section_value "$CFG" general use_radarr true raw;       assert_rc 0 $? "general.use_radarr set"
yaml_set_section_value "$CFG" sonarr apikey "0123456789";        assert_rc 0 $? "sonarr.apikey set"
yaml_set_section_value "$CFG" sonarr ip sonarr;                  assert_rc 0 $? "sonarr.ip set"
yaml_set_section_value "$CFG" radarr apikey "abcdef0123456789abcdef0123456789"; assert_rc 0 $? "radarr.apikey set"
yaml_set_section_value "$CFG" radarr ip radarr;                  assert_rc 0 $? "radarr.ip set"

# Only those nine lines differ from the original; providers, Plex, Postgres and
# the proxy keep their own username/password/type/ip/apikey.
changed=$(diff "$ORIG" "$CFG" | grep -c '^>')
assert_eq "9" "$changed" "exactly 9 lines changed in a 334-line config"
assert_eq "$(wc -l < "$ORIG")" "$(wc -l < "$CFG")" "line count unchanged"
section() { sed -n "/^$1:/,/^[^ ]/p" "$CFG"; }
assert_eq "  type: form" "$(section auth | grep '^  type:')" "auth.type is a bare word"
assert_eq "  username: 'mladmin'" "$(section auth | grep '^  username:')" "auth.username quoted"
assert_eq "  use_sonarr: true" "$(section general | grep '^  use_sonarr:')" "use_sonarr is a boolean"
assert_eq "  apikey: '0123456789'" "$(section sonarr | grep '^  apikey:')" "digits-only key kept as a string"
assert_eq "  ip: radarr" "$(section radarr | grep '^  ip:' | sed "s/'//g")" "radarr.ip set"
assert_eq "  type: null" "$(section proxy | grep '^  type:')" "proxy.type untouched"
assert_eq "  username: ''" "$(section plex | grep '^  username:')" "plex.username untouched"
assert_eq "  ip: '*'" "$(section general | grep '^  ip:')" "general.ip untouched"
assert_eq "  ip: 127.0.0.1" "$(section plex | grep '^  ip:')" "plex.ip untouched"

# --- awkward values round-trip --------------------------------------------------
val="O'Brien & co/x\\y \$HOME"
yaml_set_section_value "$CFG" auth username "$val"; assert_rc 0 $? "special chars accepted"
assert_eq "  username: 'O''Brien & co/x\\y \$HOME'" "$(section auth | grep '^  username:')" "single quote doubled, rest literal"
if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
    parsed=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["auth"]["username"])' "$CFG")
    assert_eq "$val" "$parsed" "YAML parser reads the value back exactly"
fi

# --- missing section/key: rc 1, file untouched ---------------------------------
before=$(cat "$CFG")
yaml_set_section_value "$CFG" nosuchsection apikey x; assert_rc 1 $? "missing section -> rc 1"
yaml_set_section_value "$CFG" auth nosuchkey x;       assert_rc 1 $? "missing key -> rc 1"
yaml_set_section_value "$TMP/absent.yaml" auth type x; assert_rc 1 $? "missing file -> rc 1"
assert_eq "$before" "$(cat "$CFG")" "failed calls leave the file unchanged"

# --- a key that is a prefix of another is not confused with it -----------------
printf 'sonarr:\n  apikey_extra: a\n  apikey: b\n' > "$TMP/prefix.yaml"
yaml_set_section_value "$TMP/prefix.yaml" sonarr apikey new
assert_eq $'sonarr:\n  apikey_extra: a\n  apikey: \'new\'' "$(cat "$TMP/prefix.yaml")" "prefix key left alone"

# --- file mode is kept (rewritten in place, not replaced) ----------------------
chmod 640 "$CFG"
yaml_set_section_value "$CFG" auth type form raw
assert_eq "640" "$(stat -c %a "$CFG")" "file mode preserved"

finish_tests
