#!/bin/bash
# 90-remove: `omarchy-kids-remove --dry-run` (always — never destructive) and, only under
# LIVE_DESTRUCTIVE=1, a real removal of the wizard-made kid from 60-wizard-easy (SPEC.md §8
# item 8; docs/remove.md).
#
# `omarchy-kids-remove` itself is "Remove Kids Mode": it tears down every kid on the machine plus
# every machine-level lock (docs/remove.md — it is not a per-kid undo). Running that for real here
# would also take out $LIVE_KID1_ACCOUNT, which scenarios 10/20/30/40/50 rely on staying
# provisioned across runs, so the real (non-dry-run) step below scopes to just the wizard kid,
# using the command docs/remove.md itself names as the single-kid undo:
# `omarchy-kids-provision remove <account> --apply` (docs/provision.md's `remove` subcommand).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

account="$(vm "omarchy-kids-conf slug '$LIVE_WIZARD_KID_NAME'")"
[[ -n "$account" ]] || account="__unknown__" # never matches a real account; keeps checks below harmless

plan="$(vmroot 'omarchy-kids-remove --dry-run 2>&1')"
status=$?
check "$status" "0" "omarchy-kids-remove --dry-run exits 0"
if [[ "$plan" == *"$account"* ]]; then
  ok "dry-run plan names the wizard kid ($account)"
else
  fail "dry-run plan doesn't mention $account"
fi

if [[ "$LIVE_DESTRUCTIVE" -eq 1 ]]; then
  if vmroot "id $account >/dev/null 2>&1"; then
    vmroot "omarchy-kids-provision remove $account --apply >/tmp/live-remove.out 2>&1"

    if vmroot "id $account >/dev/null 2>&1"; then
      fail "$account still exists after removal"
    else
      ok "$account removed for real"
    fi

    if vmroot "id $LIVE_KID1_ACCOUNT >/dev/null 2>&1"; then
      ok "$LIVE_KID1_ACCOUNT is untouched"
    else
      fail "$LIVE_KID1_ACCOUNT was removed too — this must never happen"
    fi
  else
    ok "$account already gone — skipping the real removal"
  fi
else
  ok "LIVE_DESTRUCTIVE not set to 1 — real removal skipped"
fi

scenario_result 90-remove
