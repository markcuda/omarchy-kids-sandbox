#!/bin/bash
# Tests bin/omarchy-kids-apps (SPEC.md R-APPS-2..6, Appendix C; I-1, I-6):
# list state, the allowlist math (pack + apps.extra - apps.hidden),
# hide/show, the sync-db resolution and mixed (some-resolve/some-don't)
# case both install and install-queued now do first (issue #52), the
# background-install queue file, and the opt-in hide-from-mine/
# show-in-mine override files.
#
# Fully self-contained, per AGENTS.md rule 8: pacman and systemctl are
# fakes on a stub PATH that only log their argv and fake just enough
# state (an "installed packages" file, and an "unavailable packages" file
# for `pacman -Si` -- empty by default, so everything resolves until a
# test opts one out) to react to -- same shape as
# test/shell.d/assert-test.sh's stub() helper, reused here almost
# verbatim. share/ is copied from the repo (real bands.toml and packs/),
# not faked, per that same file's own reasoning -- so the AUR audit in
# those files (issue #52) is exercised as real data, not a fixture. One
# provisioned kid throughout: kid-ada, band 6-8, per AGENTS.md rule 9's fixture
# convention.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS="$DIR/bin/omarchy-kids-apps"
CONF="$DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP apps-test.sh: python3 not found"
  exit 0
fi

fail=0
pass() { echo "ok   $*"; }
fail_() {
  echo "FAIL $*"
  fail=1
}
check() { # got want label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want '$2', got '$1')"; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail_ "$3 (want to find '$2' in '$1')"; fi
}
check_not_contains() { # haystack needle label
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail_ "$3 (did not want to find '$2' in '$1')"; fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want exit $2, got $1)"; fi
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
ROOT="$TMP/root"     # OMARCHY_KIDS_ROOT
HOME_DIR="$TMP/home" # OMARCHY_KIDS_HOME
APPDIR="$TMP/applications"
STUBS="$TMP/stubs"
LOG="$TMP/log"
ARGV_LOG="$LOG/argv.log"

mkdir -p "$SHARE/bands" "$SHARE/packs" "$ETC/kids" "$HOME_DIR" "$APPDIR" "$STUBS" "$LOG"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"
touch "$ARGV_LOG" "$LOG/installed" "$LOG/unavailable"

cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada Lovelace
avatar=fox
band=6-8
EOF

# --- stub PATH -------------------------------------------------------------

stub() { # stub NAME EXTRA
  local name="$1" extra="${2:-}" f="$STUBS/$1"
  cat >"$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
  [[ -n "$extra" ]] && printf '%s\n' "$extra" >>"$f"
  echo 'exit 0' >>"$f"
  sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$ARGV_LOG#g" -e "s#__LOG__#$LOG#g" "$f"
  rm -f "$f.bak"
  chmod +x "$f"
}

# pacman -Q PKG: exit 0 (installed) if PKG is a line in $LOG/installed.
# pacman -Si PKG: exit 0 (resolves in the sync db) unless PKG is a line in
# $LOG/unavailable (empty by default -- everything resolves until a test
# opts a package out, simulating issue #52's "target not found" mirror gap).
# pacman -S --needed --noconfirm PKG...: appends every non-flag arg to
# $LOG/installed (deduplicated), so a later -Q on it succeeds.
# shellcheck disable=SC2016
stub pacman '
if [[ "$1" == "-Q" ]]; then
    grep -qxF "$2" "__LOG__/installed" 2>/dev/null && exit 0 || exit 1
fi
if [[ "$1" == "-Si" ]]; then
    grep -qxF "$2" "__LOG__/unavailable" 2>/dev/null && exit 1 || exit 0
fi
if [[ "$1" == "-S" ]]; then
    shift
    for a in "$@"; do
        case "$a" in --*) ;; *)
            grep -qxF "$a" "__LOG__/installed" 2>/dev/null || echo "$a" >> "__LOG__/installed"
        ;; esac
    done
fi
'
stub systemctl ''

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$ROOT"
export OMARCHY_KIDS_HOME="$HOME_DIR"
export OMARCHY_KIDS_APPLICATIONS_DIRS="$APPDIR"
QUEUE_FILE="$ROOT/var/lib/omarchy-kids/apps-queue"

argv_since() { # LINE_COUNT -> everything appended to argv.log since LINE_COUNT
  tail -n "+$(($1 + 1))" "$ARGV_LOG"
}
argv_lines() { wc -l <"$ARGV_LOG" | tr -d ' '; }

# --- list --------------------------------------------------------------

out="$("$APPS" list 6-8)"
check_contains "$out" "gcompris" "list 6-8: has gcompris"
check_contains "$out" "missing" "list 6-8: gcompris starts missing"

echo "gcompris-qt" >>"$LOG/installed"
out="$("$APPS" list 6-8)"
gcompris_line="$(echo "$out" | awk '/^gcompris /{print}')"
check_contains "$gcompris_line" "installed" "list 6-8: gcompris shows installed once pacman -Q says so"
tuxpaint_line="$(echo "$out" | awk '/^tuxpaint /{print}')"
check_contains "$tuxpaint_line" "missing" "list 6-8: tuxpaint still missing"

out_kid="$("$APPS" list kid-ada)"
check "$out_kid" "$out" "list kid-ada resolves to the same thing as list 6-8 (kid-ada's band)"

"$APPS" list nope-such-band >/dev/null 2>&1
check_status "$?" 2 "list: an unknown band/kid is refused"

# --- allowlist: pack, then apps.extra, minus apps.hidden --------------------
# A systemd unit (the boot-time assert) has no HOME; the allowlist must not need one.
check "$(env -u HOME "$APPS" allowlist kid-ada 2>&1)" "$("$APPS" allowlist kid-ada)" \
  "allowlist: same answer with HOME unset (the boot-time assert runs that way)"


check "$("$APPS" allowlist kid-ada)" \
  "gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram" \
  "allowlist: no overrides -> the full 6-8 pack, in pack order"

"$CONF" set kid-ada apps.extra "scratchjr" >/dev/null
check "$("$APPS" allowlist kid-ada)" \
  "gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram,scratchjr" \
  "allowlist: apps.extra is appended after the pack"

"$CONF" set kid-ada apps.hidden "supertux,scratchjr" >/dev/null
check "$("$APPS" allowlist kid-ada)" \
  "gcompris,tuxpaint,ktuberling,blinken,supertuxkart,klettres,kanagram" \
  "allowlist: apps.hidden removes from the pack AND from apps.extra"

"$CONF" set kid-ada apps.hidden "" >/dev/null
"$CONF" set kid-ada apps.extra "" >/dev/null

# --- hide / show ---------------------------------------------------------

"$APPS" hide kid-ada tuxpaint >/dev/null
check "$("$CONF" get kid-ada apps.hidden)" "tuxpaint" "hide: writes apps.hidden through the conf tool"
check_not_contains "$("$APPS" allowlist kid-ada)" "tuxpaint" "hide: tuxpaint is out of the effective allowlist"

"$APPS" hide kid-ada tuxpaint >/dev/null
check "$("$CONF" get kid-ada apps.hidden)" "tuxpaint" "hide: hiding twice is idempotent (no duplicate)"

"$APPS" show kid-ada tuxpaint >/dev/null
check "$("$CONF" get kid-ada apps.hidden)" "" "show: removes tuxpaint from apps.hidden"
check_contains "$("$APPS" allowlist kid-ada)" "tuxpaint" "show: tuxpaint is back in the effective allowlist"

"$APPS" show kid-ada never-was-hidden >/dev/null
check_status "$?" 0 "show: an app that was never hidden is a harmless no-op"

# --- install: resolves against the sync db first (issue #52's regression) -
# klettres is a real, non-AUR pack entry; stubbing it "not found" in the
# sync db simulates the live bug (a mirror/pack gap pacman -Si would also
# catch) without needing a fake pack. Only gcompris-qt is "installed" at
# this point, so this exercises the exact mixed transaction that used to
# fail whole: some targets resolve, one doesn't.

echo "klettres" >>"$LOG/unavailable"
before="$(argv_lines)"
err="$("$APPS" install 6-8 --apply 2>&1 >/dev/null)"
check_contains "$err" "klettres" "install --apply (mixed): names the unresolved package on stderr"
check_status "$?" 0 "install --apply (mixed): still exits 0"
queued_mixed="$(sort "$QUEUE_FILE" 2>/dev/null | tr '\n' ',')"
check_not_contains "$queued_mixed" "klettres" "install --apply (mixed): unresolved package is never queued"
check_contains "$queued_mixed" "ktuberling" "install --apply (mixed): every other resolvable package is still queued"
after_argv="$(argv_since "$before")"
check_contains "$after_argv" "systemctl start --no-block omarchy-kids-apps-install.service" \
  "install --apply (mixed): still starts the unit for the resolvable rest"
rm -f "$QUEUE_FILE" # not `: >`, the very next test asserts the file doesn't exist yet
: >"$LOG/unavailable"

# --- install: default only previews; never queues or starts the unit ------
# (it still runs `pacman -Q`/`pacman -Si` to work out what the plan even
# is -- that's a read, not a write, so DRY_RUN doesn't gate it.)

before="$(argv_lines)"
out="$("$APPS" install 6-8)"
check_contains "$out" "dry-run" "install (default): reports dry-run"
check_status "$?" 0 "install (default) exits 0"
[[ -f "$QUEUE_FILE" ]] && fail_ "install (default, no --apply): must not create the queue file" ||
  pass "install (default, no --apply): queue file not created"
after_argv="$(argv_since "$before")"
check_not_contains "$after_argv" "pacman -S " "install (default, no --apply): never calls pacman -S"
check_not_contains "$after_argv" "systemctl" "install (default, no --apply): never starts the unit"

err="$("$APPS" install 6-8 2>&1 >/dev/null)"
check_contains "$err" "tuxpaint" "install 6-8: names the AUR-only tuxpaint on stderr (issue #52 audit)"

# --- install --apply: queues the missing (non-AUR) packages, starts the unit

before="$(argv_lines)"
"$APPS" install 6-8 --apply >/dev/null
[[ -f "$QUEUE_FILE" ]] && pass "install --apply: queue file created" || fail_ "install --apply: queue file missing"
queued="$(sort "$QUEUE_FILE" 2>/dev/null | tr '\n' ',')"
# gcompris-qt was already "installed" above; tuxpaint is aur:-marked (issue
# #52 audit) so it's skipped, not queued; ktuberling/blinken/supertux/
# supertuxkart/klettres/kanagram were not installed.
want_queued="$(printf '%s\n' ktuberling blinken supertux supertuxkart klettres kanagram | sort | tr '\n' ',')"
check "$queued" "$want_queued" "install --apply: queues exactly the missing, resolvable, non-AUR packages"
after_argv="$(argv_since "$before")"
check_contains "$after_argv" "systemctl start --no-block omarchy-kids-apps-install.service" \
  "install --apply: starts the background unit"
check_not_contains "$after_argv" "pacman -S " "install --apply (no --now): never calls pacman -S itself"

# a second --apply is idempotent (queue doesn't grow duplicate entries)
"$APPS" install 6-8 --apply >/dev/null
queued2="$(sort "$QUEUE_FILE" 2>/dev/null | tr '\n' ',')"
check "$queued2" "$want_queued" "install --apply: queuing twice doesn't duplicate entries"

: >"$QUEUE_FILE"

# --- install --now --apply: runs pacman directly, right away ---------------

before="$(argv_lines)"
"$APPS" install 6-8 --now --apply >/dev/null
after_argv="$(argv_since "$before")"
check_contains "$after_argv" "pacman -S --needed --noconfirm" "install --now --apply: calls pacman -S directly"
[[ -s "$QUEUE_FILE" ]] && fail_ "install --now: must not also queue anything" ||
  pass "install --now: queue file left empty"

for pkg in tuxpaint ktuberling blinken supertux supertuxkart klettres kanagram; do
  echo "$pkg" >>"$LOG/installed"
done
sort -u "$LOG/installed" -o "$LOG/installed"

out="$("$APPS" install 6-8)"
check_contains "$out" "nothing left to install" "install: nothing to do once everything is installed"

# --- AUR packages are named and skipped, never queued or installed ---------

before="$(argv_lines)"
err="$("$APPS" install 9-12 --apply 2>&1 >/dev/null)"
check_contains "$err" "AUR" "install 9-12: mentions the skipped AUR package(s) on stderr"
check_contains "$err" "turbowarp-desktop-bin" "install 9-12: names the skipped AUR package"
queued_912="$(cat "$ROOT/var/lib/omarchy-kids/apps-queue" 2>/dev/null || true)"
check_not_contains "$queued_912" "turbowarp" "install 9-12: an AUR package's pkg name is never queued"
: >"$QUEUE_FILE"

# --- install-queued: worker installs what's still missing, empties the queue

printf 'kstars\nsonic-pi\ngcompris-qt\n' >"$QUEUE_FILE" # gcompris-qt already "installed"
before="$(argv_lines)"
"$APPS" install-queued >/dev/null
after_argv="$(argv_since "$before")"
check_contains "$after_argv" "pacman -S --needed --noconfirm" "install-queued: calls pacman for the still-missing ones"
check_not_contains "$after_argv" "-S --needed --noconfirm gcompris-qt kstars sonic-pi" \
  "install-queued: doesn't ask pacman to reinstall what's already installed (sanity on arg shape)"
check "$(cat "$QUEUE_FILE" 2>/dev/null || true)" "" "install-queued: empties the queue file after a successful run"

# idempotent: running again on an empty queue is a no-op
out="$("$APPS" install-queued)"
check_contains "$out" "queue is empty" "install-queued: an empty queue is a no-op"

# --- install-queued: the mixed case (issue #52) -- resolves before pacman -S

echo "kiwix-desktop" >>"$LOG/unavailable"
printf 'ktouch\nkiwix-desktop\n' >"$QUEUE_FILE"
before="$(argv_lines)"
err="$("$APPS" install-queued 2>&1 >/dev/null)"
after_argv="$(argv_since "$before")"
check_contains "$err" "kiwix-desktop" "install-queued (mixed): names the unresolved package on stderr"
check_contains "$after_argv" "pacman -S --needed --noconfirm ktouch" \
  "install-queued (mixed): still installs the resolvable package"
check_not_contains "$after_argv" "-S --needed --noconfirm ktouch kiwix-desktop" \
  "install-queued (mixed): never hands pacman the unresolved target"
check "$(cat "$QUEUE_FILE" 2>/dev/null || true)" "" \
  "install-queued (mixed): still empties the queue (an unresolved entry won't resolve on retry either)"
: >"$LOG/unavailable"

# --- hide-from-mine / show-in-mine ------------------------------------------

"$CONF" set kid-ada apps.hidden "" >/dev/null # full pack allowlist again
cat >"$APPDIR/org.gcompris.GCompris.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=GCompris
Exec=gcompris-qt
Icon=gcompris
EOF
cat >"$APPDIR/tuxpaint.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Tux Paint
Exec=tuxpaint
Icon=tuxpaint
EOF
mkdir -p "$HOME_DIR/.local/share/applications"
cat >"$HOME_DIR/.local/share/applications/my-own-override.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Something the parent hid themselves
NoDisplay=true
EOF

APPS_DIR_OUT="$HOME_DIR/.local/share/applications"

out="$("$APPS" hide-from-mine)"
check_contains "$out" "dry-run" "hide-from-mine (default): reports dry-run"
[[ -f "$APPS_DIR_OUT/org.gcompris.GCompris.desktop" ]] && fail_ "hide-from-mine (no --apply): must not write yet" ||
  pass "hide-from-mine (no --apply): nothing written yet"

"$APPS" hide-from-mine --apply >/dev/null
[[ -f "$APPS_DIR_OUT/org.gcompris.GCompris.desktop" ]] && pass "hide-from-mine --apply: wrote the GCompris override" ||
  fail_ "hide-from-mine --apply: GCompris override missing"
[[ -f "$APPS_DIR_OUT/tuxpaint.desktop" ]] && pass "hide-from-mine --apply: wrote the Tux Paint override" ||
  fail_ "hide-from-mine --apply: Tux Paint override missing"
check_contains "$(cat "$APPS_DIR_OUT/org.gcompris.GCompris.desktop")" "NoDisplay=true" \
  "hide-from-mine --apply: override sets NoDisplay=true"
check_contains "$(cat "$APPS_DIR_OUT/org.gcompris.GCompris.desktop")" "X-OmarchyKidsHideFromMine=true" \
  "hide-from-mine --apply: override carries the internal marker"
check_contains "$(cat "$APPS_DIR_OUT/org.gcompris.GCompris.desktop")" "Exec=gcompris-qt" \
  "hide-from-mine --apply: override keeps the app's own Exec= (still usable, just not listed)"

before_count="$(find "$APPS_DIR_OUT" -maxdepth 1 -name '*.desktop' | wc -l | tr -d ' ')"
check "$before_count" "3" "hide-from-mine --apply: exactly two overrides written, plus the parent's pre-existing one"

"$APPS" show-in-mine --apply >/dev/null
[[ -f "$APPS_DIR_OUT/org.gcompris.GCompris.desktop" ]] && fail_ "show-in-mine --apply: GCompris override should be gone" ||
  pass "show-in-mine --apply: GCompris override removed"
[[ -f "$APPS_DIR_OUT/tuxpaint.desktop" ]] && fail_ "show-in-mine --apply: Tux Paint override should be gone" ||
  pass "show-in-mine --apply: Tux Paint override removed"
[[ -f "$APPS_DIR_OUT/my-own-override.desktop" ]] && pass "show-in-mine --apply: leaves the parent's own unrelated override alone" ||
  fail_ "show-in-mine --apply: must not remove a file without our marker"

exit $fail
