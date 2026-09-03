#!/bin/bash
# Static checks for PKGBUILD, omarchy-kids.install, the pacman hook, and the
# two desktop entries (issue #8: R-FND-1, R-BUILD-2, R-BUILD-4, R-TRUST-5).
# Everything here is a static/text check or a syntax-only parse: nothing
# runs makepkg, pacman, or root-only commands, so this passes on macOS too.
set -uo pipefail
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
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
  # (AGENTS.md rule 8) and never sits through omarchy-kids-ask-grownup's
  # default 15s hold -- issue #11 built the real thing behind these flags,
  # this file only checks it still fails closed with no profile.
  session_tmp="$(mktemp -d)"
  OMARCHY_KIDS_ETC="$session_tmp/etc" OMARCHY_KIDS_RUN_DIR="$session_tmp/run" \
    OMARCHY_KIDS_ASK_GROWNUP_SLEEP=0 "$session" >/dev/null 2>&1
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

echo "pkgbuild-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
