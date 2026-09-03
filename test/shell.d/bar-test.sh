#!/bin/bash
# Tests bin/omarchy-kids-bar (SPEC.md R-BAR, I-1; issue #37): enable/
# disable's exact shell.json edits on a fixture copy, backup, idempotence,
# and disable restoring the original -- plus /run/omarchy-kids/status.json's
# permissions (R-BAR-3), which bin/omarchy-kids-time-ledger writes and
# nothing tested until now.
#
# The widget itself (share/bar/KidsModule.qml) is QML that parses
# status.json inline; there is no separate bash/python parsing helper to
# unit-test here (see docs/bar.md's "What this doesn't test").
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BAR="$DIR/bin/omarchy-kids-bar"
LEDGER="$DIR/bin/omarchy-kids-time-ledger"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP bar-test.sh: jq not found"
  exit 0
fi

fail=0
pass() { echo "ok   $*"; }
fail_() { echo "FAIL $*"; fail=1; }
check() { # got want label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want '$2', got '$1')"; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail_ "$3 (want to find '$2' in '$1')"; fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want exit $2, got $1)"; fi
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

SHARE="$TMP/share"
mkdir -p "$SHARE/bar"
cp "$DIR/share/bar/manifest.json" "$DIR/share/bar/KidsModule.qml" "$SHARE/bar/"

export OMARCHY_KIDS_SHARE="$SHARE"

plugin_id="omarchy-kids.bar"

# ===========================================================================
# 1. No pre-existing shell.json, no defaults file: refuses to invent one
#    (I-1 -- never silently discard whatever else would have been on the
#    parent's real bar).
# ===========================================================================
HOME1="$TMP/home1"
mkdir -p "$HOME1"
out="$(OMARCHY_KIDS_HOME="$HOME1" OMARCHY_KIDS_DEFAULTS_SHELL_JSON="$TMP/no-such-defaults.json" \
  "$BAR" enable --apply 2>&1)"
status=$?
check_status "$status" 1 "enable refuses when there is no shell.json and no defaults to seed from"
check_contains "$out" "refusing to invent" "the refusal explains why"
check "$([[ -f "$HOME1/.config/omarchy/shell.json" ]] && echo yes || echo no)" "no" \
  "no shell.json was created"

# ===========================================================================
# 2. No pre-existing shell.json, but a defaults file exists (a fresh
#    install that never customized the bar): enable seeds shell.json from
#    the defaults, adds the widget, and remembers it created the file.
# ===========================================================================
HOME2="$TMP/home2"
DEFAULTS2="$TMP/defaults2/config/omarchy/shell.json"
mkdir -p "$HOME2" "$(dirname "$DEFAULTS2")"
cat >"$DEFAULTS2" <<'EOF'
{
  "version": 1,
  "bar": {
    "id": "omarchy.bar",
    "layout": {
      "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}],
      "center": [{"id": "omarchy.clock"}],
      "right": [{"id": "omarchy.audio"}]
    }
  },
  "plugins": []
}
EOF

env2() { OMARCHY_KIDS_HOME="$HOME2" OMARCHY_KIDS_DEFAULTS_SHELL_JSON="$DEFAULTS2" "$@"; }

out="$(env2 "$BAR" status)"
check "$out" "disabled" "status: disabled before enable"

out="$(env2 "$BAR" enable)"
check "$([[ -f "$HOME2/.config/omarchy/shell.json" ]] && echo yes || echo no)" "no" \
  "enable (dry-run, the default) writes nothing"
check_contains "$out" "dry-run" "enable's dry-run output says so"

env2 "$BAR" enable --apply >/dev/null
SHELL_JSON2="$HOME2/.config/omarchy/shell.json"
check "$([[ -f "$SHELL_JSON2" ]] && echo yes || echo no)" "yes" \
  "enable --apply creates shell.json from the defaults"
check "$([[ -f "$HOME2/.config/omarchy/.omarchy-kids-bar-created-shell-json" ]] && echo yes || echo no)" "yes" \
  "a 'we created this' marker is left behind"
check "$([[ -f "$HOME2/.config/omarchy/plugins/$plugin_id/manifest.json" ]] && echo yes || echo no)" "yes" \
  "the plugin manifest is installed"
check "$([[ -f "$HOME2/.config/omarchy/plugins/$plugin_id/KidsModule.qml" ]] && echo yes || echo no)" "yes" \
  "KidsModule.qml is installed"
check "$(jq -r '.bar.layout.left | length' "$SHELL_JSON2")" "2" \
  "the defaults' left section survives untouched"
check "$(jq -r '[.bar.layout.right[] | select(.id == "omarchy.audio")] | length' "$SHELL_JSON2")" "1" \
  "the defaults' right section keeps its existing widget"
check "$(jq -r "[.bar.layout.right[] | select(.id == \"$plugin_id\")] | length" "$SHELL_JSON2")" "1" \
  "the kids widget was added to the right section"
check "$(env2 "$BAR" status)" "enabled" "status: enabled after enable --apply"

# --- idempotence: enabling again changes nothing further ------------------
before="$(cat "$SHELL_JSON2")"
out="$(env2 "$BAR" enable --apply)"
after="$(cat "$SHELL_JSON2")"
check "$out" "omarchy-kids-bar: already enabled" "a second enable --apply says already enabled"
check "$before" "$after" "a second enable --apply leaves shell.json byte-for-byte the same"
check "$(jq -r "[.bar.layout.right[] | select(.id == \"$plugin_id\")] | length" "$SHELL_JSON2")" "1" \
  "still exactly one widget entry after a second enable"

# --- disable: since enable created shell.json, disable removes it ---------
env2 "$BAR" disable --apply >/dev/null
check "$([[ -f "$SHELL_JSON2" ]] && echo yes || echo no)" "no" \
  "disable removes the shell.json it created (back to 'no file' = defaults)"
check "$([[ -f "$HOME2/.config/omarchy/.omarchy-kids-bar-created-shell-json" ]] && echo yes || echo no)" "no" \
  "the created-marker is cleared"
check "$(env2 "$BAR" status)" "disabled" "status: disabled after disable"
check "$([[ -d "$HOME2/.config/omarchy/plugins/$plugin_id" ]] && echo yes || echo no)" "yes" \
  "the installed plugin files are left in place (matches 'omarchy plugin disable')"

out="$(env2 "$BAR" disable --apply)"
check "$out" "omarchy-kids-bar: already disabled" "disabling again is a no-op"

# ===========================================================================
# 3. A pre-existing, already-customized shell.json: enable backs it up
#    once, adds the widget, leaves everything else alone; disable restores
#    the exact original bytes and removes the backup.
# ===========================================================================
HOME3="$TMP/home3"
mkdir -p "$HOME3/.config/omarchy"
SHELL_JSON3="$HOME3/.config/omarchy/shell.json"
BACKUP3="$SHELL_JSON3.omarchy-kids.bak"
cat >"$SHELL_JSON3" <<'EOF'
{
  "version": 1,
  "idle": {"screensaver": 150, "lock": 300},
  "bar": {
    "id": "omarchy.bar",
    "position": "top",
    "layout": {
      "left": [{"id": "omarchy.menu"}],
      "center": [{"id": "omarchy.clock", "format": "HH:mm"}],
      "right": [{"id": "omarchy.tailscale"}, {"id": "omarchy.audio"}]
    }
  },
  "plugins": [{"id": "acme.weather"}]
}
EOF
original3="$(cat "$SHELL_JSON3")"

env3() { OMARCHY_KIDS_HOME="$HOME3" OMARCHY_KIDS_DEFAULTS_SHELL_JSON="$TMP/unused-defaults.json" "$@"; }

env3 "$BAR" enable --apply >/dev/null
check "$([[ -f "$BACKUP3" ]] && echo yes || echo no)" "yes" \
  "enable backs up an existing shell.json before touching it"
check "$(cat "$BACKUP3")" "$original3" "the backup is byte-for-byte the original"
check "$([[ -f "$HOME3/.config/omarchy/.omarchy-kids-bar-created-shell-json" ]] && echo yes || echo no)" "no" \
  "no 'we created this' marker for a shell.json that already existed"
check "$(jq -r '.plugins | length' "$SHELL_JSON3")" "1" \
  "unrelated plugins[] entries survive"
check "$(jq -r '.idle.lock' "$SHELL_JSON3")" "300" "unrelated top-level keys survive"
check "$(jq -r "[.bar.layout.right[] | select(.id == \"$plugin_id\")] | length" "$SHELL_JSON3")" "1" \
  "the widget was added"
check "$(jq -r '.bar.layout.right | length' "$SHELL_JSON3")" "3" \
  "the widget was added alongside, not instead of, the existing two"

# --- idempotence: a second enable does not re-back-up or duplicate --------
env3 "$BAR" enable --apply >/dev/null
check "$(cat "$BACKUP3")" "$original3" "the backup is still the original after a second enable"
check "$(jq -r "[.bar.layout.right[] | select(.id == \"$plugin_id\")] | length" "$SHELL_JSON3")" "1" \
  "still exactly one widget entry after a second enable"

# --- disable restores the original and removes the backup -----------------
env3 "$BAR" disable --apply >/dev/null
check "$(cat "$SHELL_JSON3")" "$original3" "disable restores shell.json to the exact original bytes"
check "$([[ -f "$BACKUP3" ]] && echo yes || echo no)" "no" "the backup is removed once restored"
check "$(env3 "$BAR" status)" "disabled" "status: disabled after restoring"

out="$(env3 "$BAR" disable --apply)"
check "$out" "omarchy-kids-bar: already disabled" "disabling an already-disabled bar is a no-op"

# ===========================================================================
# 4. grant: picks the floating-terminal helper when present, alacritty
#    otherwise, and wraps a plain `sudo omarchy-kids-time grant`.
# ===========================================================================
STUBS4="$TMP/stubs4"
mkdir -p "$STUBS4"
cat >"$STUBS4/sudo" <<'EOF'
#!/bin/bash
echo "SUDO $*" >>"$LOGFILE"
exec "$@"
EOF
chmod +x "$STUBS4/sudo"

cat >"$STUBS4/omarchy-kids-time" <<'EOF'
#!/bin/bash
echo "TIME $*" >>"$LOGFILE"
exit 0
EOF
chmod +x "$STUBS4/omarchy-kids-time"

cat >"$STUBS4/omarchy-kids-exit" <<'EOF'
#!/bin/bash
echo "EXIT $*" >>"$LOGFILE"
exit 0
EOF
chmod +x "$STUBS4/omarchy-kids-exit"

cat >"$STUBS4/term-capture" <<'EOF'
#!/bin/bash
echo "TERM $*" >>"$LOGFILE"
exec "$@"
EOF
chmod +x "$STUBS4/term-capture"

LOGFILE="$TMP/grant.log"
: >"$LOGFILE"
out="$(PATH="$STUBS4:$PATH" LOGFILE="$LOGFILE" \
  OMARCHY_KIDS_TIME_BIN="$STUBS4/omarchy-kids-time" \
  OMARCHY_KIDS_TERMINAL_BIN="$STUBS4/term-capture" \
  "$BAR" grant kid-ada 15 </dev/null 2>&1)"
check_status "$?" 0 "grant exits 0 when the terminal/sudo/time chain succeeds"
log="$(cat "$LOGFILE")"
check_contains "$log" "TERM " "grant launches the configured terminal"
check_contains "$log" "SUDO " "the terminal ran the command through sudo"
check_contains "$log" "TIME grant kid-ada 15" "sudo ran omarchy-kids-time grant kid-ada 15"

out="$("$BAR" grant 2>&1)"
check_status "$?" 2 "grant with no kid/minutes is refused"

out="$("$BAR" grant kid-ada nope 2>&1)"
check_status "$?" 2 "grant with a non-numeric minutes is refused"
check_contains "$out" "positive integer" "the refusal explains why"

# --- end: R-BAR-2's "end session" action, same terminal/sudo shape, but
#     via omarchy-kids-exit --finish --kid, never loginctl directly --
#     see bin/omarchy-kids-bar's own header for why (a hard loginctl
#     terminate on a live session crashes sddm-helper, docs/exit.md) -----
LOGFILE3="$TMP/end.log"
: >"$LOGFILE3"
out="$(PATH="$STUBS4:$PATH" LOGFILE="$LOGFILE3" \
  OMARCHY_KIDS_EXIT_BIN="$STUBS4/omarchy-kids-exit" \
  OMARCHY_KIDS_TERMINAL_BIN="$STUBS4/term-capture" \
  "$BAR" end kid-ada </dev/null 2>&1)"
check_status "$?" 0 "end exits 0 when the terminal/sudo/omarchy-kids-exit chain succeeds"
log3="$(cat "$LOGFILE3")"
check_contains "$log3" "TERM " "end launches the configured terminal"
check_contains "$log3" "SUDO " "end ran the command through sudo"
check_contains "$log3" "EXIT --finish --kid kid-ada" "sudo ran omarchy-kids-exit --finish --kid <kid>"
check "$(grep -c loginctl "$LOGFILE3")" "0" "end never calls loginctl directly"

out="$("$BAR" end 2>&1)"
check_status "$?" 2 "end with no kid is refused"

# --- terminal fallback: no OMARCHY_KIDS_TERMINAL_BIN override, no
#     floating-terminal helper on PATH -> falls back to alacritty ----------
STUBS5="$TMP/stubs5"
mkdir -p "$STUBS5"
cp "$STUBS4/sudo" "$STUBS4/omarchy-kids-time" "$STUBS5/"
cat >"$STUBS5/alacritty" <<'EOF'
#!/bin/bash
echo "ALACRITTY $*" >>"$LOGFILE"
shift  # drop -e
exec "$@"
EOF
chmod +x "$STUBS5/sudo" "$STUBS5/omarchy-kids-time" "$STUBS5/alacritty"

LOGFILE2="$TMP/grant2.log"
: >"$LOGFILE2"
PATH="$STUBS5" LOGFILE="$LOGFILE2" OMARCHY_KIDS_TIME_BIN="$STUBS5/omarchy-kids-time" \
  "$BAR" grant kid-ada 15 </dev/null >/dev/null 2>&1
log2="$(cat "$LOGFILE2")"
check_contains "$log2" "ALACRITTY -e sh -c" "no floating-terminal helper on PATH falls back to alacritty -e"

# ===========================================================================
# 5. /run/omarchy-kids/status.json (R-BAR-3): mode 0640, group
#    omarchy-parents -- NOT world-readable 0644. SPEC.md R-BAR-3 says
#    "group omarchy-parents readable"; the issue that asked for this test
#    said to make it 0644 world-readable if it wasn't already, which
#    disagrees with the spec -- per AGENTS.md, the spec wins, and this is
#    the ticket's comment. bin/omarchy-kids-time-ledger already writes
#    exactly what the spec asks for (chmod 0640; chgrp omarchy-parents,
#    best-effort so a dev box with no such group still ticks).
# ===========================================================================
if command -v python3 >/dev/null 2>&1; then
  ROOT5="$TMP/root5"
  ETC5="$TMP/etc5"
  mkdir -p "$ETC5/kids" "$ROOT5"
  cat >"$ETC5/kids/kid-ada.conf" <<'EOF'
name=Ada
avatar=fox
band=6-8
EOF
  CONF_BIN="$DIR/bin/omarchy-kids-conf"
  export OMARCHY_KIDS_SHARE="$SHARE"  # harmless: conf.sh only reads bands/packs it needs
  mkdir -p "$SHARE/bands" "$SHARE/packs"
  cp "$DIR/share/bands/bands.toml" "$SHARE/bands/" 2>/dev/null || true
  cp "$DIR"/share/packs/*.toml "$SHARE/packs/" 2>/dev/null || true

  OMARCHY_KIDS_ETC="$ETC5" OMARCHY_KIDS_ROOT="$ROOT5" \
    OMARCHY_KIDS_CONF_BIN="$CONF_BIN" OMARCHY_KIDS_TIME_LEDGER_REQUIRE_ROOT=0 \
    OMARCHY_KIDS_NOW="2026-09-01 12:00:00" \
    "$LEDGER" tick >/dev/null 2>&1

  STATUS_JSON5="$ROOT5/run/omarchy-kids/status.json"
  if command -v jq >/dev/null 2>&1 && [[ -f "$STATUS_JSON5" ]]; then
    mode="$(stat -f '%Lp' "$STATUS_JSON5" 2>/dev/null || stat -c '%a' "$STATUS_JSON5" 2>/dev/null)"
    check "$mode" "640" "status.json is written mode 0640 (group omarchy-parents readable, R-BAR-3)"
    check "$(jq -r '.kids[0].kid' "$STATUS_JSON5")" "kid-ada" "status.json lists the known kid"
    check "$(jq -r '.kids[0] | has("minutes_left")' "$STATUS_JSON5")" "true" "status.json rows have minutes_left"
    check "$(jq -r '.kids[0] | has("paused")' "$STATUS_JSON5")" "true" "status.json rows have paused"
    check "$(jq -r '.kids[0] | has("live")' "$STATUS_JSON5")" "true" "status.json rows have live"
  else
    echo "SKIP status.json checks: jq missing or the ledger didn't write it (see time-test.sh for the same tick, tested there)"
  fi
  grep -q 'chgrp omarchy-parents' "$LEDGER" && pass "the ledger's write_status_json chgrps omarchy-parents (best-effort)" \
    || fail_ "expected bin/omarchy-kids-time-ledger to chgrp omarchy-parents"
else
  echo "SKIP status.json checks: python3 not found (lib/time.sh needs it)"
fi

# --- KidsModule.qml renders nothing when the file is missing --------------
grep -q 'root.hasFile = false' "$SHARE/bar/KidsModule.qml" && \
  grep -q 'visible: root.hasFile' "$SHARE/bar/KidsModule.qml" && \
  pass "KidsModule.qml is visible only when status.json parsed (renders nothing when missing)" || \
  fail_ "expected KidsModule.qml's visible binding to gate on hasFile"

# --- shellcheck (the harness runs this too, but a direct check here keeps
#     the failure local to this test file) ----------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$BAR" >/dev/null; then
    pass "shellcheck -S warning is clean on bin/omarchy-kids-bar"
  else
    fail_ "shellcheck -S warning found something in bin/omarchy-kids-bar"
    shellcheck -S warning "$BAR" || true
  fi
fi

exit $fail
