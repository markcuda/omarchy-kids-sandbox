#!/bin/bash
# Focused credential transport checks for test/live/lib.sh and scripts/vm-qmp.sh.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
LOG="$TMP/ssh.log"
FIXTURE="$TMP/fixture"
REMOTE_STUBS="$TMP/remote-stubs"
mkdir -p "$STUBS" "$FIXTURE/test/live" "$TMP/out" "$REMOTE_STUBS"
cp "$ROOT_DIR/test/live/lib.sh" "$FIXTURE/test/live/lib.sh"
cat >"$FIXTURE/test/live/config.env" <<'CFG'
LIVE_OWNER_PASSWORD=SECRET_MARKER
LIVE_SSH_CFG=/tmp/owned-ssh-config
LIVE_REMOTE_REPO=sandbox-repo
CFG

cat >"$STUBS/ssh" <<'SSH'
#!/bin/bash
printf 'argv=%s\n' "$*" >>"$HARNESS_SSH_LOG"
cat >"$HARNESS_SSH_STDIN"
if [[ "${HARNESS_SSH_EXEC:-0}" == 1 ]]; then
  command="${@: -1}"
  command="${command//\/tmp/$HARNESS_REMOTE_ROOT}"
  PATH="$HARNESS_REMOTE_STUBS:$PATH" bash -c "$command" <"$HARNESS_SSH_STDIN"
  exit $?
fi
[[ "${HARNESS_SSH_FAIL:-0}" == 1 ]] && exit 1
exit 0
SSH
cat >"$REMOTE_STUBS/cat" <<'CAT'
#!/bin/bash
if [[ "${HARNESS_REMOTE_CAT_FAIL:-0}" == 1 ]]; then
  printf partial
  exit 7
fi
if [[ "${HARNESS_REMOTE_CAT_TERM:-0}" == 1 ]]; then
  kill -TERM "$PPID"
  sleep 1
  exit 143
fi
exec /bin/cat "$@"
CAT
cat >"$REMOTE_STUBS/mv" <<'MV'
#!/bin/bash
if [[ "${HARNESS_REMOTE_MV_FAIL:-0}" == 1 ]]; then
  exit 11
fi
if [[ "${1:-}" == -fT ]]; then
  shift
  target="${@: -1}"
  if [[ "${HARNESS_REMOTE_RACE:-0}" == 1 ]]; then
    rm -f "$target"
    mkdir "$target"
  fi
  [[ ! -d "$target" ]] || exit 20
  [[ ! -L "$target" ]] || rm -f "$target"
  exec /bin/mv -f "$@"
fi
exec /bin/mv "$@"
MV
chmod +x "$STUBS/ssh" "$REMOTE_STUBS/cat" "$REMOTE_STUBS/mv"

export PATH="$STUBS:$PATH"
export HARNESS_SSH_LOG="$LOG" HARNESS_SSH_STDIN="$TMP/stdin"
export HARNESS_REMOTE_STUBS="$REMOTE_STUBS"
export OMARCHY_KIDS_VM_DRIVER_LOCKED=1

source "$FIXTURE/test/live/lib.sh"
export LIVE_OUT_DIR="$TMP/out"

fail=0
check() {
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want '$2', got '$1')"
    fail=1
  fi
}
check_contains() {
  if [[ "$1" == *"$2"* ]]; then echo "ok   $3"; else
    echo "FAIL $3 (missing '$2')"
    fail=1
  fi
}
check_not_contains() {
  if [[ "$1" != *"$2"* ]]; then echo "ok   $3"; else
    echo "FAIL $3 (found '$2')"
    fail=1
  fi
}

: >"$LOG"
vmroot 'printf target-stdin' >/dev/null
argv="$(cat "$LOG")"
check_not_contains "$argv" SECRET_MARKER "vmroot never puts the owner password in SSH argv"
check_contains "$(cat "$FIXTURE/test/live/lib.sh")" 'ssh -T -F' "vmroot disables SSH pty allocation"
check_contains "$argv" 'sudo -S' "vmroot authenticates through sudo stdin"
check_contains "$argv" '</dev/null' "vmroot gives the target command a closed stdin"
check "$(cat "$TMP/stdin")" SECRET_MARKER "vmroot sends the password only on SSH stdin"

: >"$LOG"
printf '%s' SECRET_MARKER | qmp type >/dev/null
argv="$(cat "$LOG")"
check_not_contains "$argv" SECRET_MARKER "qmp type never puts typed text in SSH argv"
check_contains "$(cat "$FIXTURE/test/live/lib.sh")" 'vm-qmp.sh type' "qmp type selects stdin mode"
check "$(cat "$TMP/stdin")" SECRET_MARKER "qmp type sends typed text on SSH stdin"
check_not_contains "$(cat "$ROOT_DIR/scripts/vm-qmp.sh")" 'text="$2"' \
  "qmp type has no legacy argv text route"

REMOTE_ROOT="$TMP/remote"
mkdir -p "$REMOTE_ROOT"
export HARNESS_REMOTE_ROOT="$REMOTE_ROOT" HARNESS_SSH_EXEC=1
printf 'safe SECRET_MARKER\n' | vm_write_file /tmp/answers.txt >/dev/null
argv="$(cat "$LOG")"
check_not_contains "$argv" SECRET_MARKER "remote answer contents never enter SSH argv"
check_contains "$(cat "$FIXTURE/test/live/lib.sh")" 'ssh -T -F' "remote answer transfer disables SSH pty allocation"
check "$(cat "$REMOTE_ROOT/answers.txt")" 'safe SECRET_MARKER' \
  "remote staging publishes the complete answer file"
printf 'victim\n' >"$REMOTE_ROOT/victim"
ln -s victim "$REMOTE_ROOT/unsafe"
printf 'overwrite SECRET_MARKER\n' | vm_write_file /tmp/unsafe >/dev/null 2>&1
check "$?" 1 "remote staging refuses a symlink destination"
check "$(cat "$REMOTE_ROOT/victim")" victim \
  "remote staging cannot overwrite a symlink target"

HARNESS_REMOTE_RACE=1 vm_write_file /tmp/race.txt <<<'race SECRET_MARKER' >/dev/null 2>&1
check "$?" 20 "remote staging rejects a destination that becomes a directory"
check "$(find "$REMOTE_ROOT" -type f -name 'race.txt' -print | wc -l | tr -d ' ')" 0 \
  "destination race cannot publish inside a directory"
unset HARNESS_REMOTE_RACE

HARNESS_REMOTE_CAT_FAIL=1 vm_write_file /tmp/cat-failure.txt <<<'failed SECRET_MARKER' >/dev/null 2>&1
check "$?" 7 "remote staging propagates a failed cat"
check "$(find "$REMOTE_ROOT" -type f -name '.cat-failure.txt.*' -print | wc -l | tr -d ' ')" 0 \
  "failed cat leaves no staged answer file"
unset HARNESS_REMOTE_CAT_FAIL

HARNESS_REMOTE_CAT_TERM=1 vm_write_file /tmp/term-failure.txt <<<'interrupted SECRET_MARKER' >/dev/null 2>&1
check "$?" 143 "remote staging reports an interrupted cat"
check "$(find "$REMOTE_ROOT" -type f -name '.term-failure.txt.*' -print | wc -l | tr -d ' ')" 0 \
  "interrupted cat leaves no staged answer file"
unset HARNESS_REMOTE_CAT_TERM

printf 'old\n' >"$REMOTE_ROOT/mv-failure.txt"
HARNESS_REMOTE_MV_FAIL=1 vm_write_file /tmp/mv-failure.txt <<<'new SECRET_MARKER' >/dev/null 2>&1
check "$?" 11 "remote staging propagates a failed mv"
check "$(cat "$REMOTE_ROOT/mv-failure.txt")" old \
  "failed mv preserves the prior destination"
check "$(find "$REMOTE_ROOT" -type f -name '.mv-failure.txt.*' -print | wc -l | tr -d ' ')" 0 \
  "failed mv cleans its staged answer file"
unset HARNESS_REMOTE_MV_FAIL

mkdir -p "$REMOTE_ROOT/race-target"
printf 'race SECRET_MARKER\n' | vm_write_file '/tmp/race-target/$(touch INJECTION_MARKER)' >/dev/null 2>&1
check "$?" 0 "remote staging accepts a literal metacharacter filename"
check_not_contains "$(find "$REMOTE_ROOT" -name INJECTION_MARKER -print)" INJECTION_MARKER \
  "remote filename cannot execute command substitution"

check_not_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" vm_tty_sudo \
  "wizard no longer stages a second credential file for the tty"
check_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" "sed -n '2p'" \
  "wizard authenticates from its existing answer file"
check_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" '</dev/null' \
  "wizard keeps the target stdin closed after sudo authentication"
check_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" 'mktemp -d /tmp/.omarchy-kids-wizard.' \
  "wizard answers use a private per-run directory"
check_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" 'WIZARD_OUTPUT_PATH' \
  "wizard output stays beside its private answers file"
wizard_source="$ROOT_DIR/test/live/60-wizard-easy.sh"
build_line="$(grep -n '^build_install' "$wizard_source" | cut -d: -f1)"
mkdir_line="$(grep -n 'mktemp -d /tmp/.omarchy-kids-wizard' "$wizard_source" | cut -d: -f1)"
check "$([[ "$mkdir_line" -gt "$build_line" ]] && echo yes || echo no)" yes \
  "wizard directory allocation waits for readiness"
check_contains "$(cat "$wizard_source")" "trap 'wizard_answers_signal INT' INT" \
  "interrupts use an explicit failing signal path"
check_contains "$(cat "$wizard_source")" "trap 'wizard_answers_signal TERM' TERM" \
  "termination uses an explicit failing signal path"
check_contains "$(cat "$wizard_source")" "trap 'wizard_answers_signal HUP' HUP" \
  "hangups use an explicit failing signal path"
check_not_contains "$(cat "$ROOT_DIR/test/live/60-wizard-easy.sh")" '|| true' \
  "wizard cleanup does not hide credential removal failure"
unset HARNESS_SSH_EXEC

HARNESS_SSH_FAIL=1 vm_write_file /tmp/answers.txt </dev/null >/dev/null 2>&1
check "$?" 1 "remote answer transport reports SSH failure"
HARNESS_SSH_FAIL=1 vmroot 'true' </dev/null >/dev/null 2>&1
check "$?" 1 "root transport reports SSH failure"

exit "$fail"
