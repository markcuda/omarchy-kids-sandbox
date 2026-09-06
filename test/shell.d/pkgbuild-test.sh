#!/bin/bash
# Static checks for PKGBUILD, omarchy-kids.install, the pacman hook, and the
# two desktop entries (issue #8: R-FND-1, R-BUILD-2, R-BUILD-4, R-TRUST-5).
# Everything here is a static/text check or a syntax-only parse: nothing
# runs makepkg, pacman, or root-only commands, so this passes on macOS too.
set -uo pipefail

# shellcheck source=test/shell.d/tree.sh
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"
pass() { echo "PASS  $*"; }
fail() {
  echo "FAIL  $*"
  rc=1
}
rc=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGBUILD="$ROOT/PKGBUILD"
INSTALL_FILE="$ROOT/omarchy-kids.install"
HOOK="$ROOT/pacman/omarchy-kids.hook"
APP_DESKTOP="$ROOT/desktop/omarchy-kids.desktop"
SESSION_DESKTOP="$ROOT/desktop/omarchy-kids-session.desktop"

# --- PKGBUILD exists and is syntactically valid bash --------------------
if [[ -f "$PKGBUILD" ]]; then
  pass "PKGBUILD exists"
  if bash -n "$PKGBUILD"; then
    pass "bash -n PKGBUILD"
  else
    fail "bash -n PKGBUILD"
  fi
else
  fail "PKGBUILD not found at $PKGBUILD"
fi

# --- PKGBUILD sources cleanly under makepkg-like stub vars ---------------
# makepkg sources PKGBUILD (defining vars + functions) before ever calling
# package(), with pkgdir/srcdir/startdir already set. Reproduce that here
# with throwaway directories so we never touch the real filesystem, and
# confirm sourcing alone (no package() call) doesn't error under set -u.
if [[ -f "$PKGBUILD" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  out="$(
    set -euo pipefail
    # makepkg pre-sets these three (not pkgname/pkgver/pkgrel -- those are
    # defined BY the PKGBUILD when sourced, so left unset here).
    # shellcheck disable=SC2034 # startdir: read by the sourced PKGBUILD
    pkgdir="$TMP/pkg" srcdir="$TMP/src" startdir="$ROOT"
    mkdir -p "$pkgdir" "$srcdir"
    # shellcheck source=/dev/null
    source "$PKGBUILD"
    # shellcheck disable=SC2154 # pkgname: set by the PKGBUILD just sourced
    if [[ "$pkgname" == "omarchy-kids" ]] && [[ "$(type -t package)" == "function" ]]; then
      echo OK
    else
      echo "BAD pkgname=$pkgname package=$(type -t package)"
    fi
  )"
  if [[ "$out" == "OK" ]]; then
    pass "PKGBUILD sources cleanly with stub pkgdir/startdir and defines package()"
  else
    fail "sourcing PKGBUILD with stub vars: $out"
  fi
fi

# --- every bin/omarchy-kids-* file is covered by package() ---------------
if [[ -f "$PKGBUILD" ]]; then
  # Text of just the package() function body (naive brace match: PKGBUILD's
  # package() is a plain one-level function, no nested `}` at column 0).
  pkg_body="$(sed -n '/^package()/,/^}/p' "$PKGBUILD")"
  if [[ -z "$pkg_body" ]]; then
    fail "no package() function found in PKGBUILD"
  elif grep -Eq 'bin/omarchy-kids-\*' <<<"$pkg_body"; then
    pass "package() installs bin/omarchy-kids-* via a glob"
  else
    missing=()
    for f in "$ROOT"/bin/omarchy-kids-*; do
      [[ -f "$f" ]] || continue
      name="$(basename "$f")"
      grep -qF "$name" <<<"$pkg_body" || missing+=("$name")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      pass "package() references every bin/omarchy-kids-* file by name"
    else
      fail "package() does not reference: ${missing[*]}"
    fi
  fi
fi

# --- omarchy-kids.install parses -----------------------------------------
if [[ -f "$INSTALL_FILE" ]]; then
  pass "omarchy-kids.install exists"
  if bash -n "$INSTALL_FILE"; then
    pass "bash -n omarchy-kids.install"
  else
    fail "bash -n omarchy-kids.install"
  fi
  for fn in post_install post_upgrade post_remove; do
    if grep -qE "^${fn}\s*\(\)" "$INSTALL_FILE"; then
      pass "omarchy-kids.install defines $fn()"
    else
      fail "omarchy-kids.install missing $fn()"
    fi
  done
else
  fail "omarchy-kids.install not found at $INSTALL_FILE"
fi

# --- pacman hook has the required keys -----------------------------------
if [[ -f "$HOOK" ]]; then
  pass "pacman/omarchy-kids.hook exists"
  for key in Type Target When Exec; do
    if grep -qE "^${key}[[:space:]]*=" "$HOOK"; then
      pass "hook has $key ="
    else
      fail "hook missing $key ="
    fi
  done
  if grep -qE '^Operation[[:space:]]*=' "$HOOK"; then
    pass "hook has at least one Operation ="
  else
    fail "hook missing Operation ="
  fi
else
  fail "pacman/omarchy-kids.hook not found at $HOOK"
fi

# The scriptlet has one intentional unit side effect: authd.socket must be
# enabled before the first wizard run, while the other units remain runtime
# responsibilities of Apply/assert.
if grep -q 'enables and starts' "$ROOT/docs/packaging.md" &&
  grep -q 'omarchy-kids-authd.socket' "$ROOT/docs/packaging.md"; then
  pass "packaging docs record authd.socket as the scriptlet exception"
else
  fail "packaging docs must record authd.socket as the scriptlet exception"
fi

# --- desktop entries have Name/Exec/Type ---------------------------------
for f in "$APP_DESKTOP" "$SESSION_DESKTOP"; do
  if [[ -f "$f" ]]; then
    pass "$(basename "$f") exists"
    for key in Name Exec Type; do
      if grep -qE "^${key}=" "$f"; then
        pass "$(basename "$f") has $key="
      else
        fail "$(basename "$f") missing $key="
      fi
    done
  else
    fail "$f not found"
  fi
done

# --- the new command stubs behave (bonus: cheap and worth having) --------
for cmd in omarchy-kids omarchy-kids-assert; do
  bin="$ROOT/bin/$cmd"
  if [[ -x "$bin" ]]; then
    if "$bin" --help >/dev/null 2>&1; then
      pass "$cmd --help exits 0"
    else
      fail "$cmd --help did not exit 0"
    fi
  else
    fail "$bin missing or not executable"
  fi
done
session="$ROOT/bin/omarchy-kids-session"
if [[ -x "$session" ]]; then
  if "$session" --help >/dev/null 2>&1; then
    pass "omarchy-kids-session --help exits 0"
  else
    fail "omarchy-kids-session --help did not exit 0"
  fi
  # Scratch env so this smoke check never reads the real /etc/omarchy-kids
  # (AGENTS.md rule 8) and never sits through omarchy-kids-blocked's
  # default 15s hold -- issue #11 built the real thing behind these flags,
  # this file only checks it still fails closed with no profile.
  session_tmp="$(mktemp -d)"
  session_tree="$session_tmp/tree"
  mkdir -p "$session_tmp/bin"
  kids_tree "$session_tree" "$ROOT"
  kids_set_const "$session_tree/bin/omarchy-kids-session" ETC "$session_tmp/etc"
  kids_set_const "$session_tree/bin/omarchy-kids-session" SHARE "$session_tmp/share"
  kids_set_const "$session_tree/bin/omarchy-kids-session" SYSROOT "$session_tmp/root"
  kids_set_const "$session_tree/bin/omarchy-kids-session" RUNTIME_DIR "$session_tmp/run"
  kids_set_const "$session_tree/bin/omarchy-kids-session" RUN_DIR "$session_tmp/run"
  kids_stub "$session_tmp" getent <<EOF
#!/bin/bash
[[ "\${1:-}" == passwd ]] || exit 1
printf 'fixture:x:1000:1000::%s:/bin/bash\\n' "$session_tmp/home"
EOF
  OMARCHY_KIDS_BLOCKED_SLEEP=0 PATH="$session_tmp/bin:$PATH" \
    "$session_tree/bin/omarchy-kids-session" >/dev/null 2>&1
  session_rc=$?
  rm -rf "$session_tmp"
  if [[ $session_rc -eq 1 ]]; then
    pass "omarchy-kids-session with no args exits 1"
  else
    fail "omarchy-kids-session with no args did not exit 1"
  fi
else
  fail "$session missing or not executable"
fi

# The app entry point has no dash suffix; the glob alone would skip it
# (found in the VM). This used to sit after `exit $rc` and never ran.
if grep -qE 'install -m755 bin/omarchy-kids bin/omarchy-kids-\*' "$ROOT/PKGBUILD"; then
  pass "PKGBUILD installs bin/omarchy-kids itself"
else
  fail "PKGBUILD must install bin/omarchy-kids (no dash suffix)"
fi

# --- review S4: the shipped verifier has no build-time test escape hatch ---
#
# bin/omarchy-kids-parent-auth honours --socket for a non-root caller only
# when the path lies under a build-time TEST_SOCKET_ROOT. That must be
# empty in every copy this package installs.
if grep -qx 'TEST_SOCKET_ROOT=""' "$ROOT/bin/omarchy-kids-parent-auth"; then
  pass "parent-auth ships with an empty build-time test socket root"
else
  fail "parent-auth's TEST_SOCKET_ROOT is not empty in the committed file (review S4)"
fi

# --- the build-time constants, and only those (AGENTS.md, "The trust
#     boundary"): the committed files carry the checkout's value, and
#     PKGBUILD rewrites the one that has to be absolute in a package.
if grep -qx 'KIDS_PY=python3' "$ROOT/lib/kids.sh"; then
  pass "lib/kids.sh ships the checkout's KIDS_PY (PATH-resolved python3)"
else
  fail "lib/kids.sh's KIDS_PY is no longer the checkout constant"
fi
# shellcheck disable=SC2016 # $DIR is the literal checkout-relative constant under test.
if grep -qx 'SCHEMA="$DIR/share/config/schema.toml"' "$ROOT/bin/omarchy-kids-conf"; then
  pass "omarchy-kids-conf ships with a checkout-relative schema constant"
else
  fail "omarchy-kids-conf's schema path is not a build-time constant"
fi
# -F: the sed script is a literal, and GNU and BSD grep disagree about
# what a backslash-escaped ^ or $ means mid-pattern.
if grep -qF 's|^KIDS_PY=python3$|KIDS_PY=/usr/bin/python3|' "$PKGBUILD"; then
  pass "package() bakes the absolute interpreter path into the installed lib/kids.sh"
else
  fail "PKGBUILD no longer substitutes KIDS_PY at package time"
fi
# shellcheck disable=SC2016 # $DIR is the literal source pattern under test.
if grep -qF 's|^SCHEMA="$DIR/share/config/schema.toml"$|SCHEMA="/usr/share/omarchy-kids/config/schema.toml"|' "$PKGBUILD"; then
  pass "package() bakes the fixed schema path into the installed command"
else
  fail "PKGBUILD no longer substitutes the schema path at package time"
fi
if grep -qx 'SYSROOT=""' "$ROOT/bin/omarchy-kids-web"; then
  pass "omarchy-kids-web ships with an empty build-time sysroot (R-WEB-4 reads the real /etc)"
else
  fail "omarchy-kids-web's SYSROOT is not empty in the committed file (review §3.8)"
fi

# --- review §6: the tui demo is not a user command (issue #56) ------------
if [[ -x "$ROOT/scripts/omarchy-kids-tui-demo" && ! -e "$ROOT/bin/omarchy-kids-tui-demo" ]]; then
  pass "omarchy-kids-tui-demo lives in scripts/, not bin/"
else
  fail "omarchy-kids-tui-demo is missing from scripts/ or still present in bin/"
fi
if grep -q 'bin/omarchy-kids bin/omarchy-kids-\*' "$PKGBUILD" && ! grep -q '^scripts/' "$PKGBUILD"; then
  pass "package() installs only bin/, never scripts/, so the demo is never shipped"
else
  fail "PKGBUILD's package() may now ship scripts/ (review §6)"
fi

# --- issue #111: the app entry refreshes gum through Omarchy's launcher ----
# The presentation helper sources omarchy-restart-gum before opening its own
# xdg-terminal-exec window, so Terminal must be false to avoid nesting one.
if grep -q '^Terminal=false$' "$ROOT/desktop/omarchy-kids.desktop"; then
  pass "desktop/omarchy-kids.desktop lets Omarchy's helper own the terminal"
else
  fail "desktop/omarchy-kids.desktop must set Terminal=false; its helper opens the terminal"
fi

if grep -q '^Exec=omarchy-launch-floating-terminal-with-presentation env OMARCHY_KIDS_LAUNCHED_BY=desktop omarchy-kids$' "$ROOT/desktop/omarchy-kids.desktop"; then
  pass "desktop entry refreshes current gum colors and marks itself as a human launch"
else
  fail "desktop/omarchy-kids.desktop must use Omarchy's presentation helper with OMARCHY_KIDS_LAUNCHED_BY"
fi

# The helper is owned by Omarchy, so the fixture owns a command with that name
# and proves the desktop command reaches it instead of launching a toast-only
# process. The installed Omarchy path is the runtime contract; no fallback
# terminal is guessed here.
HELPER_FIXTURE="$TMP/omarchy-launch-floating-terminal-with-presentation"
RESTART_FIXTURE="$TMP/omarchy-restart-gum"
cat >"$RESTART_FIXTURE" <<'EOF'
#!/bin/bash
export BACKGROUND="#1a1b26" FOREGROUND="#a9b1d6" BORDER_FOREGROUND="#7aa2f7"
EOF
chmod +x "$RESTART_FIXTURE"
cat >"$HELPER_FIXTURE" <<'EOF'
#!/bin/bash
source omarchy-restart-gum
printf '%s|%s|%s|%s\n' "$*" "$BACKGROUND" "$FOREGROUND" "$BORDER_FOREGROUND" >"${HELPER_LOG:?}"
EOF
chmod +x "$HELPER_FIXTURE"
HELPER_LOG="$TMP/helper.log"
PATH="$TMP:$PATH" BACKGROUND="#000000" FOREGROUND="#ffffff" BORDER_FOREGROUND="#ffffff" \
  HELPER_LOG="$HELPER_LOG" \
  omarchy-launch-floating-terminal-with-presentation env OMARCHY_KIDS_LAUNCHED_BY=desktop omarchy-kids
if [[ "$(cat "$HELPER_LOG")" == "env OMARCHY_KIDS_LAUNCHED_BY=desktop omarchy-kids|#1a1b26|#a9b1d6|#7aa2f7" ]]; then
  pass "desktop helper fixture refreshes stale gum colors before the app"
else
  fail "desktop helper fixture did not refresh stale gum colors and receive the app command"
fi

# --- lib/sock.sh ships: three commands source it now ----------------------
if grep -qE 'install -m644 lib/\*\.sh' "$ROOT/PKGBUILD"; then
  pass "PKGBUILD installs lib/*.sh (covers the new lib/sock.sh)"
else
  fail "PKGBUILD does not install lib/*.sh -- lib/sock.sh would be missing"
fi

echo "pkgbuild-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
