#!/bin/bash
# Tests bin/omarchy-kids-ask (SPEC.md R-ASK-1..3, Appendix D; issue #25):
# the kid-side modal launcher, submit writing into a kid's own outbox,
# root-side collect/list/approve/decline, and static syntax checks for
# systemd/omarchy-kids-ask-collect.{service,timer} (systemd-analyze may
# not be installed here, so those checks are text/parse-only, same as
# test/shell.d/pkgbuild-test.sh's approach to the pacman hook).
#
# share/ask/shell.qml itself is UNTESTED here, same as share/exit-modal/
# shell.qml in test/shell.d/exit-test.sh's own header -- no Quickshell in
# this environment. This file only checks the bash side: what env vars
# it's launched with, and what it's expected to call back into.
#
# Fully self-contained: quickshell, pgrep, omarchy-kids-conf,
# omarchy-kids-web, and omarchy-kids-time are fakes on a stub PATH that
# only log their argv and fake just enough state to react to -- same
# shape as test/shell.d/exit-test.sh's and apps-test.sh's stub() helper.
# One provisioned kid throughout: kid-ada, band 6-8 (AGENTS.md rule 9);
# a second, kid-bo, only where two-kids-at-once matters (collect).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-ask"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP ask-test.sh: python3 not found"
  exit 0
fi

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

check_eq() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}
check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2' in '$1')"; fi
}
check_not_contains() { # haystack needle label
    if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (did not want to find '$2' in '$1')"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUBS="$TMP/stubs"
LOG="$TMP/argv.log"
SHARE="$TMP/share"
ETC="$TMP/etc"
VARLIB_ROOT="$TMP/sysroot"           # OMARCHY_KIDS_ROOT
RUN_USER_ROOT="$TMP/run-user"        # OMARCHY_KIDS_RUN_USER_ROOT
CONF_STORE="$TMP/conf-store.tsv"     # fake omarchy-kids-conf's backing store
QUEUE_DIR="$VARLIB_ROOT/var/lib/omarchy-kids/queue"

mkdir -p "$STUBS" "$SHARE/ask" "$ETC/kids" "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox" \
    "$RUN_USER_ROOT/1001/omarchy-kids/ask-outbox"
touch "$LOG" "$SHARE/ask/shell.qml" "$CONF_STORE"

# stub NAME EXTRA -- see test/shell.d/exit-test.sh for the full rationale.
stub() {
    local name="$1" extra="${2:-}" f="$STUBS/$1"
    cat > "$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
    [[ -n "$extra" ]] && printf '%s\n' "$extra" >> "$f"
    echo 'exit 0' >> "$f"
    sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$LOG#g" -e "s#__STORE__#$CONF_STORE#g" "$f"
    rm -f "$f.bak"
    chmod +x "$f"
}

stub quickshell
stub pgrep 'exit 1'  # "not found" by default: no modal already up

# omarchy-kids-conf get/set, backed by a flat "kid\tkey\tvalue" append
# log (last line for a kid/key wins) -- just enough to fake apps.extra
# and band lookups without a real /etc/omarchy-kids tree.
# shellcheck disable=SC2016
stub omarchy-kids-conf '
case "$1" in
  get)
    val="$(awk -F"\t" -v k="$2" -v key="$3" "\$1==k && \$2==key {v=\$3} END{print v}" "__STORE__")"
    printf "%s\n" "$val"
    ;;
  set)
    printf "%s\t%s\t%s\n" "$2" "$3" "$4" >> "__STORE__"
    ;;
esac
'
stub omarchy-kids-web ''

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_ROOT="$VARLIB_ROOT"
export OMARCHY_KIDS_RUN_USER_ROOT="$RUN_USER_ROOT"
export OMARCHY_KIDS_CONF_BIN="$STUBS/omarchy-kids-conf"
export OMARCHY_KIDS_WEB_BIN="$STUBS/omarchy-kids-web"

argv_since() { tail -n "+$(( $1 + 1 ))" "$LOG"; }
argv_lines() { wc -l < "$LOG" | tr -d ' '; }

# =====================================================================
# --help / bad command
# =====================================================================

"$BIN" --help >/dev/null 2>&1; check_eq "$?" 0 "--help exits 0"
"$BIN" nonsense >/dev/null 2>&1; check_eq "$?" 2 "an unknown command exits 2"

# =====================================================================
# Kid-side: time/app/plugin/site open the modal with kid-words env
# =====================================================================

OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    "$BIN" time 15 >/dev/null 2>&1
argv="$(cat "$LOG")"
check_contains "$argv" "quickshell -p $SHARE/ask/shell.qml" "time: execs quickshell with the ask modal path"

cat > "$STUBS/quickshell" <<'EOF'
#!/bin/bash
{
  echo "OMARCHY_KIDS_ACCOUNT=$OMARCHY_KIDS_ACCOUNT"
  echo "OMARCHY_KIDS_ASK_KIND=$OMARCHY_KIDS_ASK_KIND"
  echo "OMARCHY_KIDS_ASK_WHAT=$OMARCHY_KIDS_ASK_WHAT"
  echo "OMARCHY_KIDS_ASK_DESC=$OMARCHY_KIDS_ASK_DESC"
  echo "OMARCHY_KIDS_ASK_MINUTES=$OMARCHY_KIDS_ASK_MINUTES"
} > "$OMARCHY_KIDS_TEST_ENV_DUMP"
EOF
chmod +x "$STUBS/quickshell"

ENV_DUMP="$TMP/env-dump"
OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_TEST_ENV_DUMP="$ENV_DUMP" "$BIN" time 15 >/dev/null 2>&1
env_out="$(cat "$ENV_DUMP" 2>/dev/null || true)"
check_contains "$env_out" "OMARCHY_KIDS_ACCOUNT=kid-ada" "time: exports OMARCHY_KIDS_ACCOUNT"
check_contains "$env_out" "OMARCHY_KIDS_ASK_KIND=time" "time: exports kind=time"
check_contains "$env_out" "OMARCHY_KIDS_ASK_WHAT=15" "time: exports what=15"
check_contains "$env_out" "OMARCHY_KIDS_ASK_MINUTES=15" "time: exports minutes=15"
check_contains "$env_out" "15 more minute" "time: description is in kid words"

: > "$ENV_DUMP"
OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_TEST_ENV_DUMP="$ENV_DUMP" "$BIN" app "minecraft" >/dev/null 2>&1
env_out="$(cat "$ENV_DUMP" 2>/dev/null || true)"
check_contains "$env_out" "OMARCHY_KIDS_ASK_KIND=app" "app: exports kind=app"
check_contains "$env_out" "OMARCHY_KIDS_ASK_WHAT=minecraft" "app: exports what=minecraft"

: > "$ENV_DUMP"
OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_TEST_ENV_DUMP="$ENV_DUMP" "$BIN" site "roblox.com" >/dev/null 2>&1
env_out="$(cat "$ENV_DUMP" 2>/dev/null || true)"
check_contains "$env_out" "OMARCHY_KIDS_ASK_KIND=site" "site: exports kind=site"
check_contains "$env_out" "OMARCHY_KIDS_ASK_WHAT=roblox.com" "site: exports what=roblox.com"

: > "$ENV_DUMP"
OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_TEST_ENV_DUMP="$ENV_DUMP" "$BIN" plugin "weather-widget" >/dev/null 2>&1
env_out="$(cat "$ENV_DUMP" 2>/dev/null || true)"
check_contains "$env_out" "OMARCHY_KIDS_ASK_KIND=plugin" "plugin: exports kind=plugin"

stub quickshell  # restore the plain argv-logging stub

# --- time: needs a positive whole number -----------------------------

"$BIN" time 0 >/dev/null 2>&1; check_eq "$?" 2 "time 0: refused"
"$BIN" time -5 >/dev/null 2>&1; check_eq "$?" 2 "time -5: refused"
"$BIN" time banana >/dev/null 2>&1; check_eq "$?" 2 "time banana: refused"

# --- already open: never execs quickshell again -----------------------

stub pgrep 'exit 0'  # "found" -- a modal is already up
before="$(argv_lines)"
OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    "$BIN" time 5 >/dev/null 2>&1; st=$?
check_eq "$st" 0 "time: a modal already up still exits 0"
if grep -qE '^quickshell ' < <(argv_since "$before"); then
    fail "time: never execs quickshell when one is already up (it did)"
else
    pass "time: never execs quickshell when one is already up"
fi
stub pgrep 'exit 1'

# =====================================================================
# submit: writes one Appendix D record into the kid's OWN outbox
# =====================================================================

OUTBOX_ADA="$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox"

OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    "$BIN" submit time 20 --state open --minutes 20 >/dev/null
files=("$OUTBOX_ADA"/*-kid-ada-time.json)
check_eq "${#files[@]}" 1 "submit (open): writes exactly one record"
rec="${files[0]}"
check_contains "$(cat "$rec")" '"kid": "kid-ada"' "submit (open): kid field"
check_contains "$(cat "$rec")" '"state": "open"' "submit (open): state=open"
check_contains "$(cat "$rec")" '"minutes": 20' "submit (open): minutes=20"
check_not_contains "$(cat "$rec")" '"by"' "submit (open): no 'by' yet -- undecided"
rm -f "$rec"

OMARCHY_KIDS_RUN="$RUN_USER_ROOT/1000/omarchy-kids" OMARCHY_KIDS_ACCOUNT="kid-ada" \
    "$BIN" submit app firefox --state approved --by keyboard >/dev/null
files=("$OUTBOX_ADA"/*-kid-ada-app.json)
check_eq "${#files[@]}" 1 "submit (approved): writes exactly one record"
rec="${files[0]}"
check_contains "$(cat "$rec")" '"state": "approved"' "submit (approved): state=approved"
check_contains "$(cat "$rec")" '"by": "keyboard"' "submit (approved): by=keyboard (the modal verified it)"
check_contains "$(cat "$rec")" '"what": "firefox"' "submit (approved): what=firefox"
rm -f "$rec"

"$BIN" submit bogus-kind something --state open >/dev/null 2>&1
check_eq "$?" 2 "submit: an unknown kind is refused"

# =====================================================================
# collect: dry-run previews, never moves anything
# =====================================================================

cat > "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000000-kid-ada-time.json" <<'EOF'
{"kid": "kid-ada", "kind": "time", "what": "10", "minutes": 10, "asked_at": 1000000000, "state": "open"}
EOF

out="$("$BIN" collect)"
check_contains "$out" "dry-run" "collect (default): previews only"
[[ -e "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000000-kid-ada-time.json" ]] \
    && pass "collect (default): outbox file left in place" \
    || fail "collect (default): outbox file must not move without --apply"
[[ -d "$QUEUE_DIR" && -n "$(find "$QUEUE_DIR" -name '*.json' 2>/dev/null)" ]] \
    && fail "collect (default): must not create a queue record" \
    || pass "collect (default): queue stays empty"

# =====================================================================
# collect --apply: moves outbox -> queue, applies pre-approved records
# =====================================================================

rm -f "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000000-kid-ada-time.json"  # the dry-run fixture above

# kid-ada, band 6-8 (for the site case below)
printf 'kid-ada\tband\t6-8\n' >> "$CONF_STORE"
printf 'kid-bo\tband\t6-8\n' >> "$CONF_STORE"

# open (time): collected, but left alone -- no time/conf/web call
cat > "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000001-kid-ada-time.json" <<'EOF'
{"kid": "kid-ada", "kind": "time", "what": "10", "minutes": 10, "asked_at": 1000000001, "state": "open"}
EOF
# approved (app): from kid-ada's outbox, on the spot via keyboard
cat > "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000002-kid-ada-app.json" <<'EOF'
{"kid": "kid-ada", "kind": "app", "what": "minecraft", "asked_at": 1000000002, "state": "approved", "decided_at": 1000000002, "by": "keyboard"}
EOF
# approved (site): from kid-bo's outbox (a different uid), on the spot
cat > "$RUN_USER_ROOT/1001/omarchy-kids/ask-outbox/1000000003-kid-bo-site.json" <<'EOF'
{"kid": "kid-bo", "kind": "site", "what": "roblox.com", "asked_at": 1000000003, "state": "approved", "decided_at": 1000000003, "by": "keyboard"}
EOF

stub omarchy-kids-time ''  # present on PATH: time grants can actually apply
before="$(argv_lines)"
out="$("$BIN" collect --apply)"
check_contains "$out" "3 request(s) collected" "collect --apply: collects all three records across both kids"
check_contains "$out" "2 applied" "collect --apply: applies the two pre-approved records"

[[ -e "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000001-kid-ada-time.json" ]] \
    && fail "collect --apply: must empty kid-ada's outbox" \
    || pass "collect --apply: kid-ada's outbox is empty afterward"
[[ -e "$RUN_USER_ROOT/1001/omarchy-kids/ask-outbox/1000000003-kid-bo-site.json" ]] \
    && fail "collect --apply: must empty kid-bo's outbox" \
    || pass "collect --apply: kid-bo's outbox is empty afterward"

[[ -f "$QUEUE_DIR/1000000001-kid-ada-time.json" ]] && pass "collect --apply: open record landed in the queue" \
    || fail "collect --apply: open record missing from the queue"
check_contains "$(cat "$QUEUE_DIR/1000000001-kid-ada-time.json")" '"state": "open"' \
    "collect --apply: an open record is left open (not auto-decided)"

after_argv="$(argv_since "$before")"
check_not_contains "$after_argv" "time grant kid-ada 10" \
    "collect --apply: does NOT grant time for the still-open record"

check_contains "$after_argv" "omarchy-kids-conf set kid-ada apps.extra minecraft" \
    "collect --apply: applies the approved app grant via apps.extra"
check_contains "$after_argv" "omarchy-kids-web install 6-8 --allow" \
    "collect --apply: applies the approved site grant via omarchy-kids-web install"
check_contains "$after_argv" "--apply" "collect --apply: re-installs the web policy for real"

allow_file="$ETC/kids/kid-bo/allow.txt"
[[ -f "$allow_file" ]] && check_contains "$(cat "$allow_file")" "roblox.com" \
    "collect --apply: records the per-kid site grant in allow.txt" \
    || fail "collect --apply: kid-bo/allow.txt was not written"

# a second collect on an empty set of outboxes is a harmless no-op
out2="$("$BIN" collect --apply)"
check_contains "$out2" "0 request(s) collected" "collect --apply: idempotent once outboxes are empty"

# =====================================================================
# collect --apply: omarchy-kids-time missing -- degrades, never fails
# =====================================================================

rm -f "$STUBS/omarchy-kids-time"
cat > "$RUN_USER_ROOT/1000/omarchy-kids/ask-outbox/1000000004-kid-ada-time.json" <<'EOF'
{"kid": "kid-ada", "kind": "time", "what": "5", "minutes": 5, "asked_at": 1000000004, "state": "approved", "decided_at": 1000000004, "by": "keyboard"}
EOF
err="$("$BIN" collect --apply 2>&1 >/dev/null)"
check_contains "$err" "omarchy-kids-time isn't installed yet" \
    "collect --apply: names the missing command and degrades gracefully"
[[ -f "$QUEUE_DIR/1000000004-kid-ada-time.json" ]] \
    && pass "collect --apply: the record still lands in the queue even though time couldn't apply" \
    || fail "collect --apply: record missing from the queue"

# =====================================================================
# list: only open (undecided) requests, all kids or one
# =====================================================================

out="$("$BIN" list)"
check_contains "$out" "kid-ada" "list: shows kid-ada's open request"
check_contains "$out" "time" "list: shows the kind"
check_not_contains "$out" "minecraft" "list: never shows an already-decided (approved) record"

out_ada="$("$BIN" list kid-ada)"
check_contains "$out_ada" "kid-ada" "list kid-ada: shows kid-ada"

out_bo="$("$BIN" list kid-bo)"
check_contains "$out_bo" "no open requests" "list kid-bo: nothing open for kid-bo"

# =====================================================================
# approve / decline: one keystroke, act on an id from `list`
# =====================================================================

id="1000000001-kid-ada-time"  # the still-open time request from above

before="$(argv_lines)"
"$BIN" approve "$id" >/dev/null
check_contains "$(cat "$QUEUE_DIR/$id.json")" '"state": "open"' \
    "approve (default, no --apply): does not decide yet"

stub omarchy-kids-time ''  # back on PATH for the approve/decline checks
"$BIN" approve "$id" --apply >/dev/null
after_argv="$(argv_since "$before")"
check_contains "$after_argv" "time grant kid-ada 10" "approve --apply: performs the action (time grant)"
rec="$(cat "$QUEUE_DIR/$id.json")"
check_contains "$rec" '"state": "approved"' "approve --apply: marks the record approved"
check_contains "$rec" '"by": "panel"' "approve --apply: by=panel (a human, from the panel, decided this one)"

"$BIN" approve "$id" --apply >/dev/null 2>&1
check_eq "$?" 2 "approve: an already-decided id is refused"

"$BIN" approve "no-such-id" --apply >/dev/null 2>&1
check_eq "$?" 2 "approve: an unknown id is refused"

# decline: marks declined, never performs the action
cat > "$QUEUE_DIR/1000000005-kid-ada-site.json" <<'EOF'
{"kid": "kid-ada", "kind": "site", "what": "example.com", "asked_at": 1000000005, "state": "open"}
EOF
before="$(argv_lines)"
"$BIN" decline "1000000005-kid-ada-site" --apply >/dev/null
after_argv="$(argv_since "$before")"
check_not_contains "$after_argv" "example.com" "decline --apply: never touches allow.txt or web"
check_contains "$(cat "$QUEUE_DIR/1000000005-kid-ada-site.json")" '"state": "declined"' \
    "decline --apply: marks the record declined"
check_contains "$(cat "$QUEUE_DIR/1000000005-kid-ada-site.json")" '"by": "panel"' \
    "decline --apply: by=panel"

# =====================================================================
# static: systemd/omarchy-kids-ask-collect.{service,timer}
# =====================================================================

SERVICE="$ROOT_DIR/systemd/omarchy-kids-ask-collect.service"
TIMER="$ROOT_DIR/systemd/omarchy-kids-ask-collect.timer"

if [[ -f "$SERVICE" ]]; then
    pass "omarchy-kids-ask-collect.service exists"
    grep -qE '^\[Service\]' "$SERVICE" && pass "service: has [Service]" || fail "service: missing [Service]"
    grep -qE '^Type=oneshot' "$SERVICE" && pass "service: Type=oneshot" || fail "service: missing Type=oneshot"
    grep -qE '^ExecStart=.*omarchy-kids-ask collect --apply' "$SERVICE" \
        && pass "service: ExecStart runs 'omarchy-kids-ask collect --apply'" \
        || fail "service: ExecStart does not run collect --apply"
else
    fail "$SERVICE not found"
fi

if [[ -f "$TIMER" ]]; then
    pass "omarchy-kids-ask-collect.timer exists"
    grep -qE '^\[Timer\]' "$TIMER" && pass "timer: has [Timer]" || fail "timer: missing [Timer]"
    grep -qE '^OnUnitActiveSec=1min' "$TIMER" && pass "timer: fires every minute" || fail "timer: missing OnUnitActiveSec=1min"
    grep -qE '^Unit=omarchy-kids-ask-collect\.service' "$TIMER" \
        && pass "timer: points at omarchy-kids-ask-collect.service" \
        || fail "timer: missing/wrong Unit="
    grep -qE '^\[Install\]' "$TIMER" && pass "timer: has [Install]" || fail "timer: missing [Install]"
    grep -qE '^WantedBy=timers\.target' "$TIMER" && pass "timer: WantedBy=timers.target" || fail "timer: missing WantedBy=timers.target"
else
    fail "$TIMER not found"
fi

if command -v systemd-analyze >/dev/null 2>&1; then
    if systemd-analyze verify "$SERVICE" "$TIMER" >/dev/null 2>&1; then
        pass "systemd-analyze verify: service + timer are syntactically valid"
    else
        fail "systemd-analyze verify: service or timer failed verification"
    fi
else
    pass "systemd-analyze not available here -- static [Section]/key checks above stand in for it"
fi

# --- PKGBUILD installs the timer, and share/ask ---------------------------

PKGBUILD="$ROOT_DIR/PKGBUILD"
if [[ -f "$PKGBUILD" ]]; then
    pkg_body="$(sed -n '/^package()/,/^}/p' "$PKGBUILD")"
    grep -qE 'systemd/\*\.timer' <<<"$pkg_body" \
        && pass "PKGBUILD: package() installs systemd/*.timer" \
        || fail "PKGBUILD: package() does not install *.timer"
    grep -qE 'cp -a share/\.' <<<"$pkg_body" \
        && pass "PKGBUILD: package() copies all of share/ (covers share/ask/)" \
        || fail "PKGBUILD: package() does not copy share/ wholesale"
else
    fail "$PKGBUILD not found"
fi

[[ -f "$ROOT_DIR/share/ask/shell.qml" ]] && pass "share/ask/shell.qml exists" || fail "share/ask/shell.qml missing"

echo "ask-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
