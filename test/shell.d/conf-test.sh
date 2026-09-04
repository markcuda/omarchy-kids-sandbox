#!/bin/bash
# Tests bin/omarchy-kids-conf, lib/conf.sh, and lib/conf.py (SPEC.md
# R-BAND-1, R-BAND-2, R-BUILD-5, R-CONFIG-1/2/6, Appendix B, Appendix C).
# Self-contained: runs entirely against scratch OMARCHY_KIDS_ETC and
# OMARCHY_KIDS_SHARE trees, so it never touches the real /etc or
# /usr/share. share/ is copied from the repo rather than faked, so this
# also exercises the real bands.toml and packs/ this issue ships.
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP conf-test.sh: python3 not found"
  exit 0
fi

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
mkdir -p "$SHARE/bands" "$SHARE/config" "$SHARE/packs"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR/share/config/schema.toml" "$SHARE/config/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"
mkdir -p "$SHARE/avatars"
cp "$DIR/share/avatars/fox.svg" "$SHARE/avatars/"

# issue #53: a scratch system themes dir ($OMARCHY_PATH/themes) for
# `theme`'s validation and `theme_apply_for`'s own file copy, plus a
# scratch home root so that copy never touches this box's real /home.
OMARCHY_PATH="$TMP/omarchy"
mkdir -p "$OMARCHY_PATH/themes/tokyo-night" "$OMARCHY_PATH/themes/catppuccin-latte"
echo 'background = "#1a1b26"' >"$OMARCHY_PATH/themes/tokyo-night/colors.toml"
echo 'background = "#eff1f5"' >"$OMARCHY_PATH/themes/catppuccin-latte/colors.toml"
OMARCHY_KIDS_HOME_ROOT="$TMP/homeroot"
mkdir -p "$OMARCHY_KIDS_HOME_ROOT/home/kid-ada"

# A base toolset only: a real Omarchy box already has a kid-ada account,
# and `getent passwd kid-ada` would send theme_apply_for at the real
# /home/kid-ada instead of the scratch root (AGENTS.md, testing rules).
BASE_PATH="$(kids_base_path "$TMP/base")"
export PATH="$BASE_PATH"

export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_PATH
export OMARCHY_KIDS_HOME_ROOT

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want '$2', got '$1')"
    fail=1
  fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want to find '$2' in '$1')"
    fail=1
  fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want exit $2, got $1)"
    fail=1
  fi
}

# --- schema parity --------------------------------------------------------

expected_keys=(
  name avatar band level web dns budget_min budget_min_weekend
  lights_out lights_out_weekend wifi history_visible menu theme allowlist sites
  password onboarded apps.extra apps.hidden apps.show_missing
)
schema_keys="$(python3 - "$SHARE/config/schema.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as schema_file:
    schema = tomllib.load(schema_file)
for entry in schema.get("key", []):
    print(entry["key"])
PY
)"
expected_key_text="$(printf '%s\n' "${expected_keys[@]}")"
check "$schema_keys" "$expected_key_text" "schema: declares every profile and extension key once in CLI order"

schema_metadata="$(python3 - "$SHARE/config/schema.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as schema_file:
    schema = tomllib.load(schema_file)
for entry in schema["key"]:
    required = "yes" if entry["required"] else "no"
    print("\t".join((
        entry["key"], entry["type"], required, entry["default_source"],
        entry["group"], entry["label"], entry["editor"], entry["validator"],
    )))
PY
)"
check_contains "$schema_metadata" $'name\tstring\tyes\tnone\tIdentity\tName\ttext\tnonempty-single-line' \
  "schema: name declares its type, required state, source, label, group, editor, and validator"
check_contains "$schema_metadata" $'level\tenum\tno\tband\tDesktop\tDesktop level\tenum\tlevel' \
  "schema: level declares band precedence and its editor metadata"
check_contains "$schema_metadata" $'allowlist\tcsv\tno\tpack\tApps\tStarter apps\tlauncher-list\tlauncher-ids' \
  "schema: allowlist declares pack precedence and its editor metadata"

for key in "${expected_keys[@]}"; do
  count="$(printf '%s\n' "$schema_keys" | grep -cxF "$key")"
  check "$count" "1" "schema: $key occurs exactly once"
done

# --- bands / band ---------------------------------------------------------

out="$("$CONF" bands)"
check_contains "$out" "3-5" "bands lists 3-5"
check_contains "$out" "6-8" "bands lists 6-8"
check_contains "$out" "9-12" "bands lists 9-12"
check_contains "$out" "13+" "bands lists 13+"
check_contains "$out" "Pre-reader" "bands shows the 3-5 blurb"

out="$("$CONF" band 6-8)"
check_contains "$out" "level=1" "band 6-8 has level=1"
check_contains "$out" "web=garden" "band 6-8 has web=garden"
check_contains "$out" "budget_min=60" "band 6-8 has budget_min=60"
check_contains "$out" "lights_out=19:30" "band 6-8 has lights_out=19:30"
check_contains "$out" "lights_out_weekend=20:00" "band 6-8 weekend lights-out is 30 min later"
check_contains "$out" "terminal=none" "band 6-8 has no terminal"

out="$("$CONF" band 9-12)"
check_contains "$out" "level=2" "band 9-12 has level=2"
check_contains "$out" "wifi=helper" "band 9-12 has the safe wifi helper"
check_contains "$out" "terminal=playground" "band 9-12 has a playground terminal"

"$CONF" band nope-such-band >/dev/null 2>&1
check_status "$?" 2 "band with a bad name exits 2"

# --- slug (Appendix B.1) --------------------------------------------------

check "$("$CONF" slug Ada)" "kid-ada" "slug: Ada -> kid-ada"
check "$("$CONF" slug "Zoë  O'Brien")" "kid-zoeobrien" "slug: transliterates and drops non-alphanumerics"
LONG40="$(printf 'a%.0s' {1..40})"
slug_long="$("$CONF" slug "$LONG40")"
check "${#slug_long}" "28" "slug: a 40-char name is truncated to a 24-char slug (kid- + 24)"
check "$slug_long" "kid-$(printf 'a%.0s' {1..24})" "slug: truncated slug is the first 24 chars"

# --- set: fixture profile (kid-ada, band 6-8 per AGENTS.md) ---------------

"$CONF" set kid-ada name Ada >/dev/null
"$CONF" set kid-ada avatar fox >/dev/null
"$CONF" set kid-ada band 6-8 >/dev/null
"$CONF" set kid-ada theme tokyo-night >/dev/null
check_status "$?" 0 "set writes the identity keys"

# Band and pack sources remain authoritative; the schema supplies only their source.
band_keys=(level web dns budget_min budget_min_weekend lights_out lights_out_weekend wifi history_visible menu)
for band in 3-5 6-8 9-12 13+; do
  "$CONF" set kid-ada band "$band" >/dev/null
  for key in "${band_keys[@]}"; do
    expected="$("$CONF" band "$band" | awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }')"
    check "$("$CONF" get kid-ada "$key")" "$expected" "schema precedence: $band $key comes from bands.toml"
  done
  expected="$(python3 "$DIR/lib/conf.py" pack-ids "$SHARE/packs/$band.toml")"
  check "$("$CONF" get kid-ada allowlist)" "$expected" "schema precedence: $band allowlist comes from its pack"
  expected="$(python3 "$DIR/lib/conf.py" pack-sites "$SHARE/packs/$band.toml")"
  check "$("$CONF" get kid-ada sites)" "$expected" "schema precedence: $band sites come from its pack"
done
"$CONF" set kid-ada band 6-8 >/dev/null

# --- get: override -> band -> default fallback ----------------------------

check "$("$CONF" get kid-ada level)" "1" "get: level falls back to band 6-8's default (1)"
check "$("$CONF" get kid-ada web)" "garden" "get: web falls back to band default (garden)"
check "$("$CONF" get kid-ada onboarded)" "no" "get: onboarded falls back to the global default (no)"
check "$("$CONF" get kid-ada password)" "set" "get: password falls back to the global default (set)"
check "$("$CONF" get kid-ada allowlist)" \
  "gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram" \
  "get: allowlist falls back to the band's pack"

"$CONF" set kid-ada level 2 >/dev/null
check "$("$CONF" get kid-ada level)" "2" "get: an override wins over the band default"

# --- set: validation -------------------------------------------------------

"$CONF" set kid-ada level 9 >/dev/null 2>&1
check_status "$?" 2 "set: out-of-range level is refused"

"$CONF" set kid-ada web open-everything >/dev/null 2>&1
check_status "$?" 2 "set: a bad web value is refused"

"$CONF" set kid-ada lights_out "9pm" >/dev/null 2>&1
check_status "$?" 2 "set: a non-HH:MM lights_out is refused"

err="$("$CONF" set kid-ada frobnicate yes 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "set: an unknown key is refused"
check_contains "$err" "frobnicate" "set: the refusal names the bad key"

err="$("$CONF" get kid-ada frobnicate 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "get: an unknown key is also refused"

"$CONF" set kid-ada budget_min 75 >/dev/null
check "$("$CONF" get kid-ada budget_min)" "75" "set: a valid budget_min is written and read back"

# Every schema validator accepts the current shape and rejects its old bad shape.
valid_values=(
  "name|Ada" "avatar|fox" "band|6-8" "level|1" "web|garden"
  "dns|cloudflare-family" "budget_min|60" "budget_min_weekend|60"
  "lights_out|19:30" "lights_out_weekend|20:00" "wifi|parent"
  "history_visible|yes" "menu|trimmed" "theme|tokyo-night"
  "allowlist|gcompris" "sites|example.com" "password|set" "onboarded|no"
  "apps.extra|gcompris" "apps.hidden|gcompris" "apps.show_missing|no"
)
for pair in "${valid_values[@]}"; do
  key="${pair%%|*}"
  value="${pair#*|}"
  "$CONF" set kid-ada "$key" "$value" >/dev/null 2>&1
  check "$?" "0" "schema validation: accepts $key's current valid shape"
done

invalid_values=(
  "name|" "avatar|Bad Id" "avatar|not-an-avatar"
  "band|7-9" "level|0" "web|open-everything" "dns|custom:"
  "budget_min|0" "budget_min_weekend|1441" "lights_out|9pm"
  "lights_out_weekend|24:00" "wifi|child" "history_visible|maybe"
  "menu|all" "theme|Not A Real Theme" "theme|no-such-theme"
  "allowlist|not an id" "sites|not a host" "password|ask"
  "onboarded|maybe" "apps.extra|not an id" "apps.hidden|not an id"
  "apps.show_missing|maybe"
)
for pair in "${invalid_values[@]}"; do
  key="${pair%%|*}"
  value="${pair#*|}"
  "$CONF" set kid-ada "$key" "$value" >/dev/null 2>&1
  check "$?" "2" "schema validation: rejects $key's old invalid shape"
done

# Restore the source mix used by the existing show assertions.
source "$DIR/lib/conf.sh"
conf_del "$ETC/kids/kid-ada.conf" onboarded
conf_del "$ETC/kids/kid-ada.conf" wifi
"$CONF" set kid-ada level 2 >/dev/null


# --- theme (issue #53): validation, get, and the real apply side effect ----

check "$("$CONF" get kid-ada theme)" "tokyo-night" "get: theme reads back the fixture's override"

"$CONF" set kid-ada theme "Not A Real Theme" >/dev/null 2>&1
check_status "$?" 2 "set: a theme name with spaces/caps is refused before it ever checks the themes dir"

err="$("$CONF" set kid-ada theme no-such-theme 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "set: a lowercase-shaped but non-existent theme is refused"
check_contains "$err" "no-such-theme" "set: the refusal names the bad theme"
check_contains "$err" "$OMARCHY_PATH/themes" "set: the refusal names where it looked"

"$CONF" set kid-ada theme catppuccin-latte >/dev/null
check "$("$CONF" get kid-ada theme)" "catppuccin-latte" "set: a real installed theme is accepted and read back"

KID_THEME_DIR="$OMARCHY_KIDS_HOME_ROOT/home/kid-ada/.local/state/omarchy/current/theme"
check "$(cat "$KID_THEME_DIR/colors.toml" 2>/dev/null)" "$(cat "$OMARCHY_PATH/themes/catppuccin-latte/colors.toml")" \
  "set theme: theme_apply_for actually copied the new theme's colors.toml to disk"
check "$(cat "$OMARCHY_KIDS_HOME_ROOT/home/kid-ada/.local/state/omarchy/current/theme.name" 2>/dev/null)" "catppuccin-latte" \
  "set theme: theme.name on disk matches what was just set"

# put kid-ada back on tokyo-night for the rest of this file's fixtures
"$CONF" set kid-ada theme tokyo-night >/dev/null

# get-with-no-override still behaves like name/avatar/band (theme joined
# REQUIRED_KEYS, docs/conf.md) -- a second, fresh kid that's never had
# `theme` set at all.
"$CONF" set kid-notheme name Notheme >/dev/null
"$CONF" set kid-notheme avatar fox >/dev/null
"$CONF" set kid-notheme band 6-8 >/dev/null
"$CONF" get kid-notheme theme >/dev/null 2>&1
check_status "$?" 2 "get: theme with no override at all exits 2, same as name/avatar/band"

# --- show: source column ----------------------------------------------------
# Match on the key at the start of the line and the source at the end,
# rather than the exact column widths, so this doesn't break if the
# formatting ever changes.

out="$("$CONF" show kid-ada)"
check "$(echo "$out" | awk '/^level[ \t]/{print $NF}')" "override" "show: an overridden key is marked override"
check "$(echo "$out" | awk '/^wifi[ \t]/{print $NF}')" "band" "show: a band-derived key is marked band"
check "$(echo "$out" | awk '/^onboarded[ \t]/{print $NF}')" "default" "show: a global-default key is marked default"

# --- reset: keeps identity keys, clears the rest ----------------------------

"$CONF" set kid-ada onboarded yes >/dev/null
"$CONF" set kid-ada password set >/dev/null
"$CONF" set kid-ada menu full >/dev/null
"$CONF" reset kid-ada >/dev/null

profile="$ETC/kids/kid-ada.conf"
check "$(grep -c '^name=' "$profile")" "1" "reset: name survives"
check "$(grep -c '^avatar=' "$profile")" "1" "reset: avatar survives"
check "$(grep -c '^band=' "$profile")" "1" "reset: band survives"
check "$(grep -c '^theme=' "$profile")" "1" "reset: theme survives (issue #53)"
check "$(grep -c '^password=' "$profile")" "1" "reset: password survives"
check "$(grep -c '^onboarded=' "$profile")" "1" "reset: onboarded survives"
check "$(grep -c '^level=' "$profile")" "0" "reset: level override is cleared"
check "$(grep -c '^menu=' "$profile")" "0" "reset: menu override is cleared"
check "$("$CONF" get kid-ada level)" "1" "reset: level reads back as the band default again"
check "$("$CONF" get kid-ada onboarded)" "yes" "reset: onboarded keeps its value across reset"

# --- profile file permissions (spec 5.1: root 0644) -------------------------

mode="$(kids_file_mode "$profile")"
check "$mode" "644" "profile file is mode 0644"

# --- machine set parent: recording the parent's LUKS slot (docs/boot.md
#     step 5, lib/kids.sh's luks_slots_record_parent) -- without a "0="
#     line, a boot unlocked with the parent's own disk password lands on
#     the portal instead of their desktop -------------------------------

SLOTS_FILE="$ETC/luks-slots"

# Fresh file: no luks-slots at all yet.
rm -f "$SLOTS_FILE"
"$CONF" machine set parent mark >/dev/null
check "$(cat "$SLOTS_FILE" 2>/dev/null)" "0=mark" \
  "machine set parent: a fresh luks-slots gets a 0=<parent> line"
slots_mode="$(kids_file_mode "$SLOTS_FILE")"
check "$slots_mode" "600" "machine set parent: luks-slots stays mode 0600"

# Existing kid entries are kept, not clobbered, by the same write.
rm -f "$SLOTS_FILE"
printf '3=kid-ada\n5=kid-ben\n' >"$SLOTS_FILE"
"$CONF" machine set parent mark >/dev/null
check "$(grep -c '^3=kid-ada$' "$SLOTS_FILE")" "1" \
  "machine set parent: an existing kid entry survives the parent-slot write"
check "$(grep -c '^5=kid-ben$' "$SLOTS_FILE")" "1" \
  "machine set parent: a second existing kid entry survives too"
check "$(grep -c '^0=mark$' "$SLOTS_FILE")" "1" \
  "machine set parent: 0=<parent> is added alongside the kid entries"

# An existing 0= line is left alone, even one naming someone else.
rm -f "$SLOTS_FILE"
printf '0=someone-else\n3=kid-ada\n' >"$SLOTS_FILE"
err="$("$CONF" machine set parent mark 2>&1 >/dev/null)"
check_status "$?" 0 "machine set parent: an existing 0= line naming someone else doesn't fail the command"
check "$(cat "$SLOTS_FILE")" "$(printf '0=someone-else\n3=kid-ada')" \
  "machine set parent: the existing 0= line (and the rest of the file) is left untouched"
check_contains "$err" "left it alone" \
  "machine set parent: leaving an existing 0= line alone is noted on stderr"

# Slot 0 already claimed by a provisioned kid (kid-ada, set up above):
# refuses outright rather than clash with that kid's own LUKS slot.
rm -f "$SLOTS_FILE"
printf '0=kid-ada\n' >"$SLOTS_FILE"
err="$("$CONF" machine set parent mark 2>&1 >/dev/null)"
check_status "$?" 2 "machine set parent: a kid already on slot 0 makes the command fail"
check_contains "$err" "kid-ada" "machine set parent: the refusal names the kid holding slot 0"
check "$(cat "$SLOTS_FILE")" "0=kid-ada" \
  "machine set parent: refusing to clash leaves the kid's slot-0 line untouched"

rm -f "$SLOTS_FILE"

# --- machine set parent (issue #46: the wizard's Apply step writes this
#     before anything else, so omarchy-kids-authd and omarchy-kids-provision
#     both have a parent to check against) -----------------------------

MACHINE_CONF="$ETC/machine.conf"
out="$("$CONF" machine set parent mark)"
st=$?
check "$st" "0" "machine set parent exits 0"
check "$out" "machine: parent=mark" "machine set parent echoes what it wrote"
check "$(cat "$MACHINE_CONF" 2>/dev/null)" "parent=mark" "machine set parent creates machine.conf with the right line"
machine_mode="$(kids_file_mode "$MACHINE_CONF")"
check "$machine_mode" "644" "machine.conf is mode 0644, same as a kid's profile"

# idempotent, and in-place: a second write replaces the value, not appends.
"$CONF" machine set parent dana >/dev/null
check "$(cat "$MACHINE_CONF" 2>/dev/null)" "parent=dana" "machine set parent replaces the value in place, doesn't append a second line"
check "$(grep -c '^parent=' "$MACHINE_CONF")" "1" "machine set parent: still exactly one parent= line"

"$CONF" machine set parent "" >/dev/null 2>&1
check "$?" "2" "machine set parent rejects an empty value"

"$CONF" machine bogus parent mark >/dev/null 2>&1
check "$?" "2" "an unknown machine subcommand exits 2"

"$CONF" machine set bogus mark >/dev/null 2>&1
check "$?" "2" "an unknown machine key exits 2"

# sudo strips OMARCHY_PATH; the theme validation must not die on it (seen live 2026-09-03).
err="$(env -u OMARCHY_PATH "$CONF" set kid-ada theme tokyo-night 2>&1 >/dev/null)"
check "$?" "0" "set theme with OMARCHY_PATH unset exits 0"
[[ "$err" != *"unbound variable"* ]] && clean=0 || clean=1
check "$clean" "0" "set theme with OMARCHY_PATH unset prints no unbound-variable error"

# A profile change rebuilds the kid's session manifest on a provisioned box (the sessions dir
# exists), so the next login does not fail closed on a stale manifest (seen live 2026-09-04).
# shellcheck source=lib/kids.sh
source "$DIR/lib/kids.sh"
# shellcheck source=lib/conf.sh
source "$DIR/lib/conf.sh"
# shellcheck source=lib/launcher-map.sh
source "$DIR/lib/launcher-map.sh"
# shellcheck source=lib/session-manifest.sh
source "$DIR/lib/session-manifest.sh"
CONF_BIN="$CONF" LIB="$DIR/lib" KIDS_PY=python3 KIDS_DIR="$ETC/kids" SYSROOT="$TMP/sysroot"
export OMARCHY_KIDS_ROOT="$SYSROOT" # the map builder scans <root>/usr/share/applications, never this box's
mkdir -p "$ETC/sessions" "$ETC/launchers" "$SYSROOT" "$SHARE/avatars"
[[ -e "$SHARE/avatars/fox.svg" ]] || cp "$DIR/share/avatars/fox.svg" "$SHARE/avatars/fox.svg"
if session_manifest_build kid-ada 2>"$TMP/mf.err"; then
  "$CONF" set kid-ada budget_min 45 >/dev/null
  check "$(jq -r '.budget_min' "$ETC/sessions/kid-ada.json")" "45" "set: the session manifest follows the profile change"
else
  check "built" "not built: $(tr "\n" " " <"$TMP/mf.err" | cut -c1-400)" "set: a manifest could be built for the fixture kid"
fi
rm -rf "$ETC/sessions"
"$CONF" set kid-ada budget_min 60 >/dev/null
check "$?" "0" "set: no sessions dir (not provisioned) is not an error"

exit $fail
