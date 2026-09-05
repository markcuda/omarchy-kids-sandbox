#!/bin/bash
# omarchy-kids-boot-login (R-BOOTMODE-4, R-BOOTMODE-5,
# R-BOOTMODE-11, R-BOOTMODE-12): portal and missing-slot no-ops,
# validated disk mappings, fail-safe malformed input, and cleanup ownership.
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=test/shell.d/tree.sh
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"

pass() { echo "PASS  $*"; }
fail() {
  echo "FAIL  $*"
  rc=1
}
rc=0

check_status() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label (want $want, got $got)"; fi
}

check_file() {
  local file="$1" text="$2" label="$3"
  if [[ -f "$file" && "$(cat "$file")" == "$text" ]]; then pass "$label"; else fail "$label"; fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TREE="$TMP/tree"
ETC="$TMP/etc/omarchy-kids"
RUN_DIR="$TMP/run/omarchy-kids"
SLOTS_FILE="$ETC/luks-slots"
KIDS_DIR="$ETC/kids"
SDDM_DIR="$TMP/etc/sddm.conf.d"
DROPIN="$SDDM_DIR/zz-omarchy-kids-autologin.conf"
MARKER="$RUN_DIR/boot-login-dropin"
STUBS="$TMP/stubs"

kids_tree "$TREE" "$ROOT"
rm -f "$TREE/lib"
cp -a "$ROOT/lib" "$TREE/lib"
BIN="$TREE/bin/omarchy-kids-boot-login"
kids_set_const "$TREE/lib/boot-mode.sh" BOOT_MODE_MACHINE_CONF "$ETC/machine.conf"
kids_set_const "$BIN" BOOT_LOGIN_RUN_DIR "$RUN_DIR"
kids_set_const "$BIN" BOOT_LOGIN_SLOTS_FILE "$SLOTS_FILE"
kids_set_const "$BIN" BOOT_LOGIN_KIDS_DIR "$KIDS_DIR"
kids_set_const "$BIN" BOOT_LOGIN_SDDM_DIR "$SDDM_DIR"

mkdir -p "$ETC" "$RUN_DIR" "$KIDS_DIR" "$SDDM_DIR" "$STUBS"
chmod 0755 "$ETC" "$RUN_DIR" "$KIDS_DIR" "$SDDM_DIR"
printf 'band=6-8\n' >"$KIDS_DIR/kid-ada.conf"
chmod 0644 "$KIDS_DIR/kid-ada.conf"

kids_id_stub "$STUBS" root 0
REAL_STAT="$(command -v stat)"
cat >"$STUBS/stat" <<EOF
#!/bin/bash
if [[ "\${1:-}" == --version ]]; then exec "$REAL_STAT" "\$@"; fi
format=""
target=""
case "\${1:-}" in
  -c | -f)
    format="\${2:-}"
    target="\${3:-}"
    ;;
esac
case "\$target" in
  "$TMP"/*)
    case "\$format" in
      %u) echo 0; exit 0 ;;
      %G | %Sg) echo root; exit 0 ;;
    esac
    ;;
esac
exec "$REAL_STAT" "\$@"
EOF
chmod +x "$STUBS/stat"
BASE_PATH="$(kids_base_path "$TMP/base")"
TEST_PATH="$STUBS:$BASE_PATH"

run_boot_login() {
  env -i PATH="$TEST_PATH" "$BIN" "$@"
}

set_mode() {
  local mode="$1" parent="${2:-mark}"
  printf 'parent=%s\nboot=%s\n' "$parent" "$mode" >"$ETC/machine.conf"
  chmod 0644 "$ETC/machine.conf"
}

write_slot() {
  printf '%s\n' "$1" >"$RUN_DIR/boot-slot"
  chmod 0600 "$RUN_DIR/boot-slot"
}

printf '[Autologin]\nUser=mark\nSession=omarchy.desktop\n' >"$SDDM_DIR/10-omarchy-autologin.conf"
cp "$SDDM_DIR/10-omarchy-autologin.conf" "$TMP/stock-autologin.before"

# Portal mode does not create, replace, or clean any boot-login state.
set_mode portal
printf 'keep this drop-in\n' >"$DROPIN"
printf 'keep this marker\n' >"$MARKER"
run_boot_login >/dev/null 2>&1
check_status "$?" 0 "portal mode exits 0"
check_file "$DROPIN" "keep this drop-in" "portal mode leaves the Kids Mode drop-in byte-for-byte"
check_file "$MARKER" "keep this marker" "portal mode leaves the cleanup marker byte-for-byte"
run_boot_login --cleanup >/dev/null 2>&1
check_status "$?" 0 "portal cleanup exits 0"
check_file "$DROPIN" "keep this drop-in" "portal cleanup writes nothing"
cmp -s "$TMP/stock-autologin.before" "$SDDM_DIR/10-omarchy-autologin.conf" &&
  pass "portal mode preserves stock autologin" || fail "portal mode changed stock autologin"

# In disk mode, no recorded slot is also a true no-op.
set_mode disk
rm -f "$DROPIN" "$MARKER" "$RUN_DIR/boot-slot"
run_boot_login >/dev/null 2>&1
check_status "$?" 0 "missing boot-slot exits 0"
[[ ! -e "$DROPIN" && ! -e "$MARKER" ]] &&
  pass "missing boot-slot creates no drop-in or marker" || fail "missing boot-slot wrote state"
cmp -s "$TMP/stock-autologin.before" "$SDDM_DIR/10-omarchy-autologin.conf" &&
  pass "missing boot-slot preserves stock autologin" || fail "missing boot-slot changed stock autologin"

cat >"$SLOTS_FILE" <<'EOF'
0=mark
2=kid-ada:omarchy
3=kid-ben:omarchy
4=kid-test
EOF
chmod 0600 "$SLOTS_FILE"

write_slot 2
run_boot_login >/dev/null 2>&1
check_status "$?" 0 "mapped kid slot exits 0"
check_file "$DROPIN" $'[Autologin]\nUser=kid-ada\nSession=omarchy-kids.desktop' \
  "a mapped kid gets the kid session even when the map names the stock session"
[[ -f "$MARKER" ]] && pass "mapped slot records cleanup ownership" || fail "mapped slot omitted its cleanup marker"
run_boot_login --cleanup >/dev/null 2>&1
[[ ! -e "$DROPIN" && ! -e "$MARKER" ]] &&
  pass "cleanup removes the drop-in created this boot" || fail "cleanup left owned boot-login state"

write_slot 0
run_boot_login >/dev/null 2>&1
check_file "$DROPIN" $'[Autologin]\nUser=mark\nSession=omarchy.desktop' "mapped parent slot selects the stock session"
run_boot_login --cleanup >/dev/null 2>&1

write_slot 4
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "an account with no trusted role returns 1"
check_file "$DROPIN" $'[Autologin]\nUser=' "an account with no trusted role goes to the portal"
run_boot_login --cleanup >/dev/null 2>&1

write_slot 3
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "an explicit stock session cannot bless an unknown account"
check_file "$DROPIN" $'[Autologin]\nUser=' "an explicit stock session for an unknown account goes to the portal"
run_boot_login --cleanup >/dev/null 2>&1

chmod 0666 "$KIDS_DIR/kid-ada.conf"
write_slot 2
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "a user-writable kid profile cannot authorize a kid session"
check_file "$DROPIN" $'[Autologin]\nUser=' "an unsafe kid profile goes to the portal"
run_boot_login --cleanup >/dev/null 2>&1
chmod 0644 "$KIDS_DIR/kid-ada.conf"

set_mode disk kid-test
write_slot 4
run_boot_login >/dev/null 2>&1
check_status "$?" 0 "the recorded parent account exits 0"
check_file "$DROPIN" $'[Autologin]\nUser=kid-test\nSession=omarchy.desktop' \
  "the recorded parent account gets the stock session regardless of its name"
run_boot_login --cleanup >/dev/null 2>&1
set_mode disk

# A valid but unmapped slot deliberately suppresses stock autologin.
write_slot 9
run_boot_login >/dev/null 2>&1
check_status "$?" 0 "unmapped numeric slot exits 0 after selecting the portal"
check_file "$DROPIN" $'[Autologin]\nUser=' "unmapped numeric slot writes only an empty User"
run_boot_login --cleanup >/dev/null 2>&1

# Malformed disk input selects the portal but returns 1 for diagnosis.
cat >"$SLOTS_FILE" <<'EOF'
2=kid-ada
2=kid-ben
EOF
chmod 0600 "$SLOTS_FILE"
write_slot 2
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "duplicate slot mappings return 1"
check_file "$DROPIN" $'[Autologin]\nUser=' "duplicate slot mappings fail safe to the portal"
run_boot_login --cleanup >/dev/null 2>&1

cat >"$SLOTS_FILE" <<'EOF'
2=kid-ada
EOF
chmod 0600 "$SLOTS_FILE"
write_slot '2x'
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "malformed boot-slot returns 1"
check_file "$DROPIN" $'[Autologin]\nUser=' "malformed boot-slot fails safe to the portal"
run_boot_login --cleanup >/dev/null 2>&1

write_slot 2
chmod 0666 "$SLOTS_FILE"
run_boot_login >/dev/null 2>&1
check_status "$?" 1 "unsafe slot-map permissions return 1"
check_file "$DROPIN" $'[Autologin]\nUser=' "unsafe slot-map permissions fail safe to the portal"
chmod 0600 "$SLOTS_FILE"
run_boot_login --cleanup >/dev/null 2>&1

# Cleanup cannot remove a file it did not mark as its own this boot.
printf 'unowned\n' >"$DROPIN"
rm -f "$MARKER"
run_boot_login --cleanup >/dev/null 2>&1
check_file "$DROPIN" "unowned" "cleanup leaves an unmarked drop-in alone"
rm -f "$DROPIN"

run_boot_login --nonsense >/dev/null 2>&1
check_status "$?" 2 "unknown syntax exits 2"

grep -qx 'ExecStart=-/usr/bin/omarchy-kids-boot-login' "$ROOT/systemd/omarchy-kids-boot-login.service" &&
  pass "boot-login service ignores command failure before SDDM" || fail "boot-login service can hold SDDM behind command failure"
grep -qx 'ExecStart=-/usr/bin/omarchy-kids-boot-login --cleanup' "$ROOT/systemd/omarchy-kids-boot-login-cleanup.service" &&
  pass "cleanup service ignores command failure" || fail "cleanup service treats command failure as a boot failure"

echo "boot-login-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit "$rc"
