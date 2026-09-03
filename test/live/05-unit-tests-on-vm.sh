#!/bin/bash
# 05-unit-tests-on-vm: run test/all on the VM, as an ordinary user, so the two suites that can only
# skip on the macOS dev box actually run against real Arch — authd's live password checks (SPEC.md
# R-SEC-1, R-SEC-2) and wifi-test.sh section B's SO_PEERCRED boundary (R-WIFI-2). SPEC.md R-BUILD-3.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

REMOTE_DIR="/tmp/omarchy-kids-unit"
REMOTE_TAR="/tmp/omarchy-kids-unit.tar.gz"
LOCAL_TAR="$LIVE_OUT_DIR/05-checkout.tar.gz"
LOG="$LIVE_OUT_DIR/05-unit-tests-on-vm.log"

# The exact lines test/shell.d/authd-test.sh and test/shell.d/wifi-test.sh print when they bail
# out; seeing either one in a run *on the VM* means the check that matters never happened.
AUTHD_SKIP='SKIP authd-test.sh: libcrypt not loadable here -- the live-daemon password checks did not run'
WIFI_B_SKIP='SKIP wifi-test.sh section B: SO_PEERCRED not available on this platform (Linux only)'

# This scenario needs no package installed — it runs the checkout's own tests — so it only needs
# the VM up, and boots it (owner's password: no kid session wanted here) if a prior run left it off.
if vm true 2>/dev/null; then
  ok "vm is already up"
else
  boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" &&
    ok "vm booted" || fail "vm never came up"
fi

# Ship the working checkout, not air's git HEAD (build_install's `git pull`): the point is to test
# what's on this machine right now. .git, the harness's own output dir, and config.env (test-box
# passwords) all stay behind.
rm -f "$LOCAL_TAR"
if tar -czf "$LOCAL_TAR" -C "$LIVE_REPO_ROOT" \
  --exclude=.git --exclude=test/live/out --exclude=test/live/config.env . 2>/dev/null &&
  scp -q -F "$LIVE_SSH_CFG" "$LOCAL_TAR" "vm:$REMOTE_TAR" &&
  vm "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR && tar -xzf $REMOTE_TAR -C $REMOTE_DIR && rm -f $REMOTE_TAR"; then
  ok "checkout copied to $REMOTE_DIR on the vm"
  ready=1
else
  fail "could not copy the checkout to the vm"
  ready=0
fi

# `vm` is the unprivileged owner account, never root — assert it rather than assume it, because a
# suite run as root would silently pass the very peer-uid checks it is here to exercise.
uid="$(vm 'id -u' 2>/dev/null | tr -d '[:space:]')"
if [[ -n "$uid" && "$uid" != "0" ]]; then
  ok "test/all will run as a normal user (uid $uid)"
else
  fail "refusing to run test/all as uid '$uid' on the vm"
  ready=0
fi

if ((ready)); then
  vm "cd $REMOTE_DIR && bash test/all" >"$LOG" 2>&1
  status=$?
  echo "test/all output: $LOG"
  if ((status == 0)); then
    ok "test/all passed on the vm"
  else
    fail "test/all failed on the vm (exit $status)"
    tail -20 "$LOG"
  fi
else
  : >"$LOG"
fi

# Style gate, where the formatter exists (it does not on the Mac): every bash file must already
# be `shfmt -i 2 -ci` (AGENTS.md).
if vm "command -v shfmt >/dev/null"; then
  unformatted="$(vm "cd $REMOTE_DIR && shfmt -i 2 -ci -l \$(grep -rlE '^#!/bin/bash|^# shellcheck shell=bash' bin lib test scripts)" 2>/dev/null)"
  if [[ -z "$unformatted" ]]; then
    ok "every bash file is shfmt -i 2 -ci clean"
  else
    fail "shfmt would change: $(echo "$unformatted" | tr '\n' ' ')"
  fi
fi

while IFS= read -r line; do
  echo "note remote skip: $line"
done < <(grep -E '^ *SKIP' "$LOG" 2>/dev/null)

if [[ ! -s "$LOG" ]]; then
  fail "no test/all output captured -- neither skip gate could be checked"
else
  if grep -qF "$AUTHD_SKIP" "$LOG"; then
    fail "authd-test.sh's live password checks still skipped on the vm"
  else
    ok "authd-test.sh's live password checks ran on the vm"
  fi
  if grep -qF "$WIFI_B_SKIP" "$LOG"; then
    fail "wifi-test.sh section B (SO_PEERCRED) still skipped on the vm"
  else
    ok "wifi-test.sh section B ran on the vm"
  fi
fi

scenario_result 05-unit-tests-on-vm
