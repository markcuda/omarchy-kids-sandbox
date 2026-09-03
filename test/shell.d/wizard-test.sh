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
for name in omarchy-kids-provision omarchy-kids-web omarchy-kids-assert omarchy-kids-session pacman sudo; do
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
check_contains "$out" "pacman -S --noconfirm --needed" "apply installs the starter pack from cache"
check_contains "$out" "gcompris-qt" "6-8's pack pkgs are in the pacman install line"
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
check_contains "$out" "pacman -S --noconfirm --needed gcompris-qt ktuberling supertux klettres" \
    "apply installs only the chosen subset, not the whole pack"

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

# --- --help works with no terminal and no answers file needed ----------

help_out="$("$BIN" --help 2>&1)"
help_status=$?
check_status "$help_status" 0 "--help exits 0"
check_contains "$help_out" "Usage: omarchy-kids-wizard" "--help prints usage"

echo "wizard-test.sh: done"
exit $rc
