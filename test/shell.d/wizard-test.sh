#!/bin/bash
# Tests bin/omarchy-kids-wizard (SPEC.md R-WIZ-1..9; issue #19: the Easy
# path). Drives the whole flow through OMARCHY_KIDS_TUI_ANSWERS, with gum
# faked on a stub PATH (same convention as test/shell.d/tui-test.sh: it
# logs nothing interesting itself here, since --dry-run means the wizard's
# own `run_priv`/`run_priv_stdin` print every command instead of ever
# calling sudo, pacman, omarchy-kids-provision, -web, -assert, or -session
# -- so what this checks is the *text* those wrappers print, not a stub's
# argv log. Fakes for those six are still put on PATH as a safety net (a
# code path that ever ran one for real would hit a fake, not the real
# thing), but --dry-run never reaches them, which is exactly the point:
# nothing here ever touches the real /etc, /var, /home, or invokes a real
# pacman or sudo (AGENTS.md rule 8).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$DIR/bin/omarchy-kids-wizard"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP wizard-test.sh: python3 not found (needed by omarchy-kids-conf)"
    exit 0
fi

pass() { echo "PASS  $*"; }
fail() {
    echo "FAIL  $*"
    rc=1
}
rc=0

check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2' in output)"; fi
}
check_not_contains() { # haystack needle label
    if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (did not want '$2' in output)"; fi
}
check_status() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want exit $2, got $1)"; fi
}

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# --- scratch tree: real bands.toml/packs, scratch everything else ------

ETC="$TMP/etc/omarchy-kids"
SHARE="$TMP/share/omarchy-kids"
STUBS="$TMP/stubs"
ARGV_LOG="$TMP/argv.log"
mkdir -p "$ETC/kids" "$SHARE/bands" "$SHARE/packs" "$SHARE/avatars" "$STUBS"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"
cp "$DIR"/share/avatars/*.svg "$SHARE/avatars/"
: >"$ARGV_LOG"

# Fake gum: same convention as test/shell.d/tui-test.sh's own fake --
# only needed here so lib/tui.sh's header rendering has something to
# call; every actual answer in this file comes from OMARCHY_KIDS_TUI_ANSWERS,
# never from gum.
cat >"$STUBS/gum" <<'EOF'
#!/bin/bash
case "${1:-}" in
    style)
        shift
        seen=0
        for a in "$@"; do
            if [[ $seen == 1 ]]; then printf '%s\n' "$a"; fi
            [[ "$a" == "--" ]] && seen=1
        done
        ;;
    *) exit 0 ;;
esac
EOF

# Fakes for every command the Apply step (or prefetch) might shell out to:
# each just logs its own argv, one line, to $ARGV_LOG, so a dry run can be
# told apart from a run that actually reached one of these.
for name in omarchy-kids-provision omarchy-kids-web omarchy-kids-assert omarchy-kids-session omarchy-kids-apps pacman sudo; do
    cat >"$STUBS/$name" <<EOF
#!/bin/bash
echo "$name \$*" >>"$ARGV_LOG"
cat >/dev/null
exit 0
EOF
done
chmod +x "$STUBS"/*

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_PROVISION_BIN="$STUBS/omarchy-kids-provision"
export OMARCHY_KIDS_WEB_BIN="$STUBS/omarchy-kids-web"
export OMARCHY_KIDS_ASSERT_BIN="$STUBS/omarchy-kids-assert"
export OMARCHY_KIDS_SESSION_BIN="$STUBS/omarchy-kids-session"
export OMARCHY_KIDS_APPS_BIN="$STUBS/omarchy-kids-apps"
export DRY_RUN=1

answers_file() { # writes $@ (one per line) to a fresh file, prints its path
    local f="$TMP/answers.$RANDOM"
    printf '%s\n' "$@" >"$f"
    printf '%s' "$f"
}

run_wizard() { # ANSWERS_FILE -> stdout+stderr in $out, exit status in $WIZ_STATUS
    local answers="$1"
    out="$(OMARCHY_KIDS_TUI_ANSWERS="$answers" "$BIN" --dry-run 2>&1)"
    WIZ_STATUS=$?
}

# --- the whole Easy path, band 6-8, non-default web/Wi-Fi/level so the
# overrides those choices need are exercised too (R-BAND-2) --------------

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Ada owl 6-8 simple filtered default pack helper 2 secret1 secret1 apply parent)"
run_wizard "$answers"

check_status "$WIZ_STATUS" 0 "happy path exits 0"
check_contains "$out" "step 1 of 15" "Welcome is step 1"
check_contains "$out" "step 2 of 15" "Parent password is step 2, right after Welcome (A2)"
check_contains "$out" "Pick Ada's face." "the face screen (A4) is shown"
check_contains "$out" "kid-ada" "name screen previews the kid- account slug"
check_contains "$out" "step 15 of 15" "Done is the last step"
check_contains "$out" "Screen time" "summary shows the screen-time row"
check_contains "$out" "60 minutes a day" "summary shows band 6-8's budget"
check_contains "$out" "19:30" "summary shows band 6-8's bedtime"
check_contains "$out" "Face          owl" "summary shows the chosen face"

# --dry-run means Apply's run_priv/run_priv_stdin print the command
# instead of ever calling sudo/pacman/omarchy-kids-*, so this is checking
# the wizard's own "[dry-run] sudo ..." lines in $out, not a stub's argv.
check_contains "$out" "omarchy-kids-provision add Ada --band 6-8 --avatar owl --password-stdin --parent-password-stdin --apply" \
    "apply runs provision add with the exact flags, including the chosen face"
check_contains "$out" "omarchy-kids-conf set kid-ada web filtered" "a web choice that differs from the band default is written as an override"
check_contains "$out" "omarchy-kids-conf set kid-ada wifi helper" "a Wi-Fi choice that differs from the band default is written as an override"
check_contains "$out" "omarchy-kids-conf set kid-ada level 2" "a level choice that differs from the band default is written as an override"
check_contains "$out" "omarchy-kids-web install 6-8 --apply" "apply runs web install for the chosen band"
check_contains "$out" "omarchy-kids-apps install 6-8 --now --apply" "apply installs the starter pack from cache via omarchy-kids-apps, with --apply so it isn't silently a no-op under sudo"
check_contains "$out" "omarchy-kids-assert" "apply runs the safety check (assert)"
check_contains "$out" "omarchy-kids-session --check" "apply runs the session --check-equivalent safety check"
check_contains "$out" "sudo -u kid-ada" "the session check runs as the new kid's own account"

# --- every Simple choice left at the band default writes no override at
# all (R-BAND-2: "the profile stores only overrides") --------------------

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Mia fox 6-8 simple garden default pack parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "all-defaults path exits 0"
check_not_contains "$out" "omarchy-kids-conf set" "leaving every Simple choice at its band default writes no override"

# --- band 3-5: the no-password branch, and provision gets --no-password --

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Zoe fox 3-5 simple none default pack parent 1 no apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "band 3-5 no-password path exits 0"
check_contains "$out" "No password" "summary reflects the no-password choice"
check_contains "$out" "omarchy-kids-provision add Zoe --band 3-5 --avatar fox --no-password --apply" \
    "apply passes --no-password for a 3-5 kid who skipped a password"
check_not_contains "$out" "--password-stdin" "no-password path never passes --password-stdin"

# --- time (A8): "I'll set my own" asks two custom fields, validated ----

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Ada fox 6-8 simple garden custom notanumber 45 badtime 20:15 pack parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "custom screen time with bad input first still completes"
check_contains "$out" "A number of minutes, 1 to 1440." "a non-numeric budget is rejected with a reason"
check_contains "$out" "24-hour time, like 19:30." "a malformed lights-out time is rejected with a reason"
check_contains "$out" "45 minutes a day" "the summary shows the custom budget"
check_contains "$out" "20:15" "the summary shows the custom lights-out time"

# --- apps (A9): "Let me pick" walks the pack one app at a time ---------

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Ada fox 6-8 simple garden default pick yes no yes no yes no yes no parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "picking apps one at a time still completes"
check_contains "$out" "Include GCompris in Ada's starter apps?" "the checklist asks about each pack app by name"
check_contains "$out" "GCompris, KTuberling, SuperTux, KLettres" "the summary lists only the apps answered yes"
# %q escapes the commas (printf's own quoting choice, not a bug); the
# value bash would actually pass through as argv[3] is still the plain
# comma-joined list.
check_contains "$out" 'omarchy-kids-conf set kid-ada allowlist gcompris\,ktuberling\,supertux\,klettres' \
    "the chosen subset is written as the allowlist override (what shows in the launcher)"
check_contains "$out" "omarchy-kids-apps install 6-8 --now --apply" \
    "apply still installs the whole band pack regardless of the pick (R-WIZ-4: changed selections need no undo); the allowlist above is what actually restricts the kid to the chosen subset"

# --- name validation: digits/punctuation rejected, then a good name works -

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 "123!!" Mo fox 6-8 simple garden default pack parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "a bad name doesn't abort the wizard"
check_contains "$out" "Letters, spaces, and hyphens only" "invalid name is rejected with a reason"
check_contains "$out" "kid-mo" "the wizard proceeds once a valid name is given"

# --- Advanced says "coming next" and returns to the same screen --------

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Ada fox 6-8 advanced simple garden default pack parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "choosing Advanced then Simple still completes"
check_contains "$out" "coming next" "Advanced explains it isn't built yet"

# --- Esc from the face screen goes back to the name screen, keyboard-only

: >"$ARGV_LOG"
answers="$(answers_file begin parentpw123 Ada @esc Bea fox 6-8 simple garden default pack parent 1 secret1 secret1 apply parent)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 0 "Esc-back then finishing still exits 0"
check_contains "$out" "kid-bea" "the re-entered name after Esc-back is the one used"
check_contains "$out" "Pick Bea's face." "the face screen re-renders for the name entered after Esc-back"

# --- Ctrl+C right after Welcome (before anything else) leaves with
# nothing changed, no commands run and no prefetch started ---------------

: >"$ARGV_LOG"
answers="$(answers_file begin @ctrlc yes)"
run_wizard "$answers"
check_status "$WIZ_STATUS" 130 "Ctrl+C exits 130"
check_contains "$out" "Left setup. Nothing changed." "Ctrl+C shows the leave message"
check_not_contains "$out" "[dry-run]" "Ctrl+C before Apply prints no command at all"

# --- real mode (DRY_RUN=0): a failing step stops the dashboard, shows its
# last output lines, and the technical log is actually written -----------
#
# This needs its own scratch PATH: the harness's shared `sudo` fake above
# only logs and exits 0, which would make every step trivially "succeed"
# in real mode. Here `sudo` actually execs what it's given (stripping the
# few flags this wizard passes it), so a fake omarchy-kids-provision that
# exits 1 is genuinely what apply_step_account sees.

RM_TMP="$(mktemp -d)"
RM_STUBS="$RM_TMP/stubs"
RM_ETC="$RM_TMP/etc/omarchy-kids"
RM_LOG="$RM_TMP/setup.log"
mkdir -p "$RM_STUBS" "$RM_ETC/kids"

cat >"$RM_STUBS/sudo" <<'EOF'
#!/bin/bash
# A real-enough fake sudo for tests: strips the flags this wizard passes
# (-n/-v/-S/-p ARG/-u USER) and execs whatever command is left, or just
# exits 0 for a bare "sudo -v" credential warm-up (no command at all).
args=()
while (($#)); do
    case "$1" in
        -n | -v | -S) shift ;;
        -p) shift 2 ;;
        -u) shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
if ((${#args[@]} == 0)); then
    cat >/dev/null
    exit 0
fi
exec "${args[@]}"
EOF
cat >"$RM_STUBS/omarchy-kids-provision" <<'EOF'
#!/bin/bash
echo "FAKE-PROVISION: refusing on purpose (out of disk space)"
cat >/dev/null
exit 1
EOF
cat >"$RM_STUBS/omarchy-kids-web" <<'EOF'
#!/bin/bash
echo "FAKE-WEB: this must never print — Apply should have stopped already"
exit 0
EOF
cp "$STUBS/gum" "$RM_STUBS/gum"
chmod +x "$RM_STUBS"/*

rm_out="$(
    PATH="$RM_STUBS:$PATH" \
    OMARCHY_KIDS_ETC="$RM_ETC" \
    OMARCHY_KIDS_SHARE="$SHARE" \
    OMARCHY_KIDS_PROVISION_BIN="$RM_STUBS/omarchy-kids-provision" \
    OMARCHY_KIDS_WEB_BIN="$RM_STUBS/omarchy-kids-web" \
    OMARCHY_KIDS_SETUP_LOG="$RM_LOG" \
    OMARCHY_KIDS_TUI_ANSWERS="$(answers_file begin parentpw123 Ada fox 6-8 simple garden default pack parent 1 secret1 secret1 apply parent)" \
    DRY_RUN=0 "$BIN" 2>&1
)"
rm_status=$?
check_status "$rm_status" 0 "a real run still exits 0 even when Apply fails (Done still shows what happened)"
check_contains "$rm_out" "✗ Setting up Ada's account" "the failing step is marked ✗, not ✓, on a real exit-code failure"
check_contains "$rm_out" "FAKE-PROVISION: refusing on purpose" "the failing command's own output is shown (the tail)"
check_not_contains "$rm_out" "FAKE-WEB" "Apply stops at the first failure and never reaches a later step"
check_contains "$rm_out" 'Setup stopped at "Setting up Ada'"'"'s account"' "Done explains which step stopped it"
check_contains "$(cat "$RM_LOG" 2>/dev/null)" "FAKE-PROVISION: refusing on purpose" \
    "a real run actually writes the technical log at OMARCHY_KIDS_SETUP_LOG"

rm -rf "$RM_TMP"

# --- real mode: the safety check skips sudo -u <kid> ... --check when the
# account was never actually created, instead of handing sudo a user that
# doesn't exist -------------------------------------------------------

RM2_TMP="$(mktemp -d)"
RM2_STUBS="$RM2_TMP/stubs"
RM2_ETC="$RM2_TMP/etc/omarchy-kids"
mkdir -p "$RM2_STUBS" "$RM2_ETC/kids"

cat >"$RM2_STUBS/sudo" <<'EOF'
#!/bin/bash
args=()
while (($#)); do
    case "$1" in
        -n | -v | -S) shift ;;
        -p) shift 2 ;;
        -u) shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
if ((${#args[@]} == 0)); then
    cat >/dev/null
    exit 0
fi
exec "${args[@]}"
EOF
for name in omarchy-kids-provision omarchy-kids-web omarchy-kids-apps omarchy-kids-assert; do
    cat >"$RM2_STUBS/$name" <<EOF
#!/bin/bash
echo "FAKE-$name: ok (no real account created — this is a stub)"
cat >/dev/null
exit 0
EOF
done
cp "$STUBS/gum" "$RM2_STUBS/gum"
chmod +x "$RM2_STUBS"/*

rm2_out="$(
    PATH="$RM2_STUBS:$PATH" \
    OMARCHY_KIDS_ETC="$RM2_ETC" \
    OMARCHY_KIDS_SHARE="$SHARE" \
    OMARCHY_KIDS_PROVISION_BIN="$RM2_STUBS/omarchy-kids-provision" \
    OMARCHY_KIDS_WEB_BIN="$RM2_STUBS/omarchy-kids-web" \
    OMARCHY_KIDS_APPS_BIN="$RM2_STUBS/omarchy-kids-apps" \
    OMARCHY_KIDS_ASSERT_BIN="$RM2_STUBS/omarchy-kids-assert" \
    OMARCHY_KIDS_SETUP_LOG="$RM2_TMP/setup.log" \
    OMARCHY_KIDS_TUI_ANSWERS="$(answers_file begin parentpw123 Ada fox 6-8 simple garden default pack parent 1 secret1 secret1 apply parent)" \
    DRY_RUN=0 "$BIN" 2>&1
)"
rm2_status=$?
check_status "$rm2_status" 0 "real mode with every fake succeeding still exits 0"
check_contains "$rm2_out" "skipping the session check — account kid-ada does not exist" \
    "the safety check explains why it skipped, rather than handing sudo -u a nonexistent user"
check_not_contains "$rm2_out" "sudo -u kid-ada" \
    "omarchy-kids-session --check is never actually invoked for an account that doesn't exist"

rm -rf "$RM2_TMP"

# --- --help works with no terminal and no answers file needed ----------

help_out="$("$BIN" --help 2>&1)"
help_status=$?
check_status "$help_status" 0 "--help exits 0"
check_contains "$help_out" "Usage: omarchy-kids-wizard" "--help prints usage"

echo "wizard-test.sh: done"
exit $rc
