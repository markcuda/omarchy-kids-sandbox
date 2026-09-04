#!/bin/bash
# share/boot/omarchy_kids.conf (R-BOOT-2): inserts
# omarchy-kids-unlock immediately before 'encrypt' exactly once, and is a
# no-op when 'encrypt' isn't in HOOKS. Each case runs in its own subshell
# so sourcing the conf.d file in one case can't leak HOOKS into another.
set -uo pipefail
pass() { echo "PASS  $*"; }
fail() {
  echo "FAIL  $*"
  rc=1
}
rc=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/share/boot/omarchy_kids.conf"

[[ -f "$CONF" ]] || {
  fail "conf.d file not found at $CONF"
  echo "mkinitcpio-conf-test RESULT: FAIL"
  exit 1
}

# --- HOOKS with 'encrypt': inserted immediately before it, exactly once ---
out="$(
  set -u
  HOOKS=(base udev keyboard autodetect modconf block encrypt filesystems fsck)
  # shellcheck source=/dev/null
  source "$CONF"
  printf '%s\n' "${HOOKS[@]}"
)"
count="$(grep -cx 'omarchy-kids-unlock' <<<"$out")"
if [[ "$count" -eq 1 ]]; then
  pass "encrypt present: omarchy-kids-unlock inserted exactly once"
else
  fail "encrypt present: expected 1 occurrence, got $count -> $(tr '\n' ' ' <<<"$out")"
fi
before_after="$(tr '\n' ' ' <<<"$out" | grep -o 'omarchy-kids-unlock encrypt')"
if [[ -n "$before_after" ]]; then
  pass "encrypt present: inserted immediately before 'encrypt'"
else
  fail "encrypt present: not immediately before 'encrypt' -> $(tr '\n' ' ' <<<"$out")"
fi

# --- HOOKS without 'encrypt': unchanged ---
out="$(
  set -u
  HOOKS=(base udev keyboard autodetect modconf block filesystems fsck)
  orig=("${HOOKS[@]}")
  # shellcheck source=/dev/null
  source "$CONF"
  if [[ "${HOOKS[*]}" == "${orig[*]}" ]]; then echo UNCHANGED; else echo "CHANGED: ${HOOKS[*]}"; fi
)"
if [[ "$out" == "UNCHANGED" ]]; then
  pass "no encrypt: HOOKS left unchanged"
else
  fail "no encrypt: $out"
fi

# --- sourcing twice: still exactly one occurrence ---
out="$(
  set -u
  HOOKS=(base udev keyboard autodetect modconf block encrypt filesystems fsck)
  # shellcheck source=/dev/null
  source "$CONF"
  # shellcheck source=/dev/null
  source "$CONF"
  printf '%s\n' "${HOOKS[@]}"
)"
count="$(grep -cx 'omarchy-kids-unlock' <<<"$out")"
if [[ "$count" -eq 1 ]]; then
  pass "sourced twice: still exactly one occurrence (idempotent)"
else
  fail "sourced twice: expected 1 occurrence, got $count -> $(tr '\n' ' ' <<<"$out")"
fi

# --- safe under 'set -u' with HOOKS entirely unset ---
if (
  set -euo pipefail
  unset HOOKS
  # shellcheck source=/dev/null
  source "$CONF"
); then
  pass "safe under set -u with HOOKS unset"
else
  fail "sourcing under set -u with HOOKS unset exited non-zero"
fi

echo "mkinitcpio-conf-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
