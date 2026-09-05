#!/bin/bash
# Tests boot-mode transitions (R-BOOTMODE-3, R-BOOTMODE-4,
# R-BOOTMODE-9, R-BOOTMODE-10; issue #98). Every boot command is a stub
# and every fixed path is rewritten in a copied command tree.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=test/shell.d/tree.sh
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"

fail=0
pass() { echo "PASS  $*"; }
bad() {
  echo "FAIL  $*"
  fail=1
}
check_eq() {
  if [[ "$1" == "$2" ]]; then pass "$3"; else bad "$3 (got '$1', want '$2')"; fi
}
file_inode() {
  if stat --version >/dev/null 2>&1; then stat -c '%i' "$1"; else stat -f '%i' "$1"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TREE="$TMP/tree"
ROOT="$TMP/root"
ETC="$ROOT/etc/omarchy-kids"
TOOLS="$TMP/tools"
BASE="$TMP/base"
LOG="$TMP/argv.log"
STATE="$TMP/boot-state"
SLOT_STATE="$TMP/luks-state"

mkdir -p "$ETC/kids" "$ROOT/etc/mkinitcpio.conf.d" \
  "$ROOT/usr/share/omarchy-kids/boot" "$ROOT/boot/EFI/Linux" "$TOOLS"
chmod 0755 "$ETC" "$ETC/kids"
printf 'boot=portal\nparent=mark\n' >"$ETC/machine.conf"
chmod 0644 "$ETC/machine.conf"
cp "$DIR/share/boot/omarchy_kids.conf" "$ROOT/usr/share/omarchy-kids/boot/"
printf 'stale active drop-in\n' >"$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
touch "$ROOT/boot/EFI/Linux/current.efi" "$STATE"

kids_tree "$TREE" "$DIR"
rm -f "$TREE/lib"
cp -a "$DIR/lib" "$TREE/lib"
kids_set_const "$TREE/lib/boot-mode.sh" BOOT_MODE_MACHINE_CONF "$ETC/machine.conf"
kids_set_const "$TREE/lib/boot-mode.sh" BOOT_MODE_LOCK "$ROOT/run/omarchy-kids/boot-mode.lock"

if [[ -f "$TREE/lib/boot-mode-transition.sh" ]]; then
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_KIDS_DIR "$ETC/kids"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_SLOTS_FILE "$ETC/luks-slots"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_TEMPLATE "$ROOT/usr/share/omarchy-kids/boot/omarchy_kids.conf"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_DROPIN "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_UKI_DIR "$ROOT/boot/EFI/Linux"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_FINDMNT "$TOOLS/findmnt"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_LSBLK "$TOOLS/lsblk"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_CRYPTSETUP "$TOOLS/cryptsetup"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_MKINITCPIO "$TOOLS/mkinitcpio"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_LSINITCPIO "$TOOLS/lsinitcpio"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_LIMINE_CONF "$ROOT/boot/limine.conf"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_LIMINE_DEFAULT "$ROOT/etc/default/limine"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_LIMINE_SYNC "$TOOLS/limine-snapper-sync"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_MKINITCPIO_CONF "$ROOT/etc/mkinitcpio.conf"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_MKINITCPIO_CONF_DIR "$ROOT/etc/mkinitcpio.conf.d"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_ENV "$TOOLS/env"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_BASH "$TOOLS/bash"
  kids_set_const "$TREE/lib/boot-mode-transition.sh" BOOT_TRANSITION_RECOVERY "$ETC/boot-transition.recovery"
fi

kids_id_stub "$TOOLS" mark 0
REAL_STAT="$(command -v stat)"
cat >"$TOOLS/stat" <<EOF
#!/bin/bash
if [[ "\${1:-}" == --version ]]; then exec "$REAL_STAT" "\$@"; fi
[[ "\${3:-}" != "$ETC/machine.conf" ]] || printf 'stat-machine\n' >>"$LOG"
if [[ "\${3:-}" == "$ETC/machine.conf" && -e "$TMP/fail-next-mode-read" ]]; then
  rm -f "$TMP/fail-next-mode-read"
  exit 1
fi
case "\${2:-}" in
  %u) echo 0 ;;
  %G | %Sg) echo root ;;
  *) exec "$REAL_STAT" "\$@" ;;
esac
EOF
cat >"$TOOLS/chown" <<'EOF'
#!/bin/bash
exit 0
EOF
REAL_MV="$(command -v mv)"
cat >"$TOOLS/mv" <<EOF
#!/bin/bash
"$REAL_MV" "\$@" || exit 1
if [[ "\${*: -1}" == "$ETC/machine.conf" && -e "$TMP/arm-mode-readback-failure" ]]; then
  rm -f "$TMP/arm-mode-readback-failure"
  : >"$TMP/fail-next-mode-read"
fi
EOF
cat >"$TOOLS/flock" <<EOF
#!/bin/bash
printf 'flock %s\n' "\$*" >>"$LOG"
exit 0
EOF
cat >"$TOOLS/findmnt" <<'EOF'
#!/bin/bash
echo /dev/mapper/cryptroot
EOF
cat >"$TOOLS/lsblk" <<'EOF'
#!/bin/bash
printf '/dev/mapper/cryptroot btrfs\n/dev/fake0 crypto_LUKS\n'
EOF
cat >"$TOOLS/cryptsetup" <<EOF
#!/bin/bash
printf 'cryptsetup %s\n' "\$*" >>"$LOG"
case "\${1:-}" in
  luksDump)
    while IFS== read -r slot _; do
      [[ -n "\$slot" ]] && printf '%s: luks2\n' "\$slot"
    done <"$SLOT_STATE"
    ;;
  luksKillSlot)
    slot="\${*: -1}"
    [[ ! -e "$TMP/fail-kill-\$slot" ]] || exit 1
    awk -F= -v slot="\$slot" '\$1 != slot' "$SLOT_STATE" >"$SLOT_STATE.next"
    mv "$SLOT_STATE.next" "$SLOT_STATE"
    ;;
  open)
    key_file=""
    key_slot=""
    while ((\$#)); do
      case "\$1" in
        --key-file=*) key_file="\${1#--key-file=}" ;;
        --key-slot) key_slot="\${2:-}"; shift ;;
      esac
      shift
    done
    key="\$(cat "\$key_file")"
    if [[ -n "\$key_slot" ]]; then
      grep -qxF "\$key_slot=\$key" "$SLOT_STATE"
    else
      grep -qE "^[0-9]+=\$(printf '%s' "\$key" | sed 's/[][\\.^$*+?{}|()]/\\\\&/g')\$" "$SLOT_STATE"
    fi
    ;;
  luksAddKey)
    old_file=""
    key_slot=""
    new_file=""
    while ((\$#)); do
      case "\$1" in
        --key-file=*) old_file="\${1#--key-file=}" ;;
        --key-slot) key_slot="\${2:-}"; shift ;;
        /dev/fd/*) new_file="\$1" ;;
      esac
      shift
    done
    old="\$(cat "\$old_file")"
    new="\$(cat "\$new_file")"
    grep -qF "=\$old" "$SLOT_STATE" || exit 1
    [[ ! -e "$TMP/fail-add-\$key_slot" ]] || exit 1
    printf '%s=%s\n' "\$key_slot" "\$new" >>"$SLOT_STATE"
    ;;
  *) exit 0 ;;
esac
EOF
cat >"$TOOLS/mkinitcpio" <<EOF
#!/bin/bash
printf 'mkinitcpio %s\n' "\$*" >>"$LOG"
if [[ -e "$TMP/fail-mkinitcpio-once" ]]; then
  rm -f "$TMP/fail-mkinitcpio-once"
  printf 'present\n' >"$STATE"
  exit 1
fi
if [[ -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" ]]; then
  printf 'present\n' >"$STATE"
else
  printf 'absent\n' >"$STATE"
fi
if [[ -e "$TMP/corrupt-uki-after-rebuild" ]]; then
  rm -f "$TMP/corrupt-uki-after-rebuild"
  printf 'damaged\n' >"$ROOT/boot/EFI/Linux/current.efi"
  printf 'corrupt\n' >"$STATE"
fi
EOF
cat >"$TOOLS/lsinitcpio" <<EOF
#!/bin/bash
printf 'lsinitcpio %s\n' "\$*" >>"$LOG"
[[ ! -e "$TMP/fail-lsinitcpio" ]] || exit 1
[[ "\$(cat "$STATE")" != corrupt ]] || exit 1
[[ "\$(cat "$STATE")" == present ]] && echo usr/lib/initcpio/hooks/omarchy-kids-unlock
exit 0
EOF
cat >"$TOOLS/limine-snapper-sync" <<EOF
#!/bin/bash
printf 'limine-snapper-sync\n' >>"$LOG"
exit 0
EOF
chmod +x "$TOOLS"/*
ln -sf "$(command -v env)" "$TOOLS/env"
ln -sf "$(command -v bash)" "$TOOLS/bash"

PATH_VALUE="$TOOLS:$(kids_base_path "$BASE")"
CONF="$TREE/bin/omarchy-kids-conf"

: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/error"
status=$?
check_eq "$status" 0 "portal convergence exits 0"
check_eq "$(test ! -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" && echo absent)" absent \
  "portal convergence removes a stale active drop-in"
check_eq "$(grep -c '^mkinitcpio -P$' "$LOG" 2>/dev/null || true)" 1 \
  "portal convergence rebuilds once when the active hook may be stale"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "portal remains authoritative after convergence"

# Disk to portal makes portal authoritative before removing disk state,
# kills every recorded kid slot, restores its Limine marker, and rebuilds once.
printf 'boot=disk\nparent=mark\n' >"$ETC/machine.conf"
printf '0=mark\n3=kid-ada\n5=kid-cy\n' >"$ETC/luks-slots"
chmod 0600 "$ETC/luks-slots"
printf '0=parentpass\n3=adapass\n5=cypass\n' >"$SLOT_STATE"
printf 'active drop-in\n' >"$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'present\n' >"$STATE"
mkdir -p "$ROOT/etc/default"
printf '# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=10\nMAX_SNAPSHOT_ENTRIES=0\n' \
  >"$ROOT/etc/default/limine"
: >"$LOG"

PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/disk-to-portal.error"
status=$?
check_eq "$status" 0 "disk to portal exits 0"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "disk to portal leaves portal authoritative"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "disk to portal removes every kid slot and preserves the parent slot"
check_eq "$(test ! -e "$ETC/luks-slots" && echo absent)" absent \
  "disk to portal removes the slot map"
check_eq "$(test ! -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" && echo absent)" absent \
  "disk to portal removes the active drop-in"
check_eq "$(grep -c '^mkinitcpio -P$' "$LOG" 2>/dev/null || true)" 1 \
  "disk to portal rebuilds exactly once"
check_eq "$(cat "$STATE")" absent "disk to portal rebuild removes the hook"
check_eq "$(test ! -e "$ROOT/boot/EFI/Linux/current.efi.omarchy-kids-transition-backup" && echo absent)" absent \
  "disk to portal removes the verified UKI backup"
check_eq "$(cat "$ROOT/etc/default/limine")" 'MAX_SNAPSHOT_ENTRIES=10' \
  "disk to portal restores only the recorded Limine snapshot value"
check_eq "$(grep -c '^limine-snapper-sync$' "$LOG" 2>/dev/null || true)" 1 \
  "disk to portal refreshes Limine once when owned state changed"
check_eq "$(grep -c '^cryptsetup luksKillSlot --batch-mode /dev/fake0 ' "$LOG" 2>/dev/null || true)" 2 \
  "disk to portal kills exactly the two recorded kid slots"
if grep -q 'luksKillSlot.* 0$' "$LOG"; then
  bad "disk to portal tried to kill the parent slot"
else
  pass "disk to portal never kills the parent slot"
fi

: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/portal-again.error"
check_eq "$?" 0 "a converged portal rerun exits 0"
check_eq "$(grep -c '^mkinitcpio ' "$LOG" 2>/dev/null || true)" 0 \
  "a converged portal rerun does not rebuild"
check_eq "$(grep -c '^cryptsetup ' "$LOG" 2>/dev/null || true)" 0 \
  "a converged portal rerun does not inspect or mutate LUKS"

# Portal never starts destructive convergence without an inspected image,
# and restores that known-good image when the replacement cannot be verified.
printf 'boot=disk\nparent=mark\n' >"$ETC/machine.conf"
printf '0=mark\n' >"$ETC/luks-slots"
chmod 0600 "$ETC/luks-slots"
printf '0=parentpass\n' >"$SLOT_STATE"
printf 'active drop-in\n' >"$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'present\n' >"$STATE"
printf 'known-good-image\n' >"$ROOT/boot/EFI/Linux/current.efi"
: >"$TMP/corrupt-uki-after-rebuild"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/corrupt-rebuild.error"
check_eq "$?" 1 "portal rejects a rebuilt UKI that cannot be inspected"
check_eq "$(cat "$ROOT/boot/EFI/Linux/current.efi")" 'known-good-image' \
  "portal restores the known-good UKI when replacement verification fails"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a restored UKI remains under portal authority"

rm -f "$ROOT/boot/EFI/Linux/current.efi"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/missing-uki.error"
check_eq "$?" 1 "portal never accepts a missing UKI as converged"
check_eq "$(grep -c '^mkinitcpio ' "$LOG" 2>/dev/null || true)" 0 \
  "portal does not rebuild when there is no known-good UKI to preserve"

printf 'boot=disk\nparent=mark\n' >"$ETC/machine.conf"
printf 'active drop-in\n' >"$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'known-good-image\n' >"$ROOT/boot/EFI/Linux/current.efi"
: >"$TMP/fail-lsinitcpio"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/unreadable-uki.error"
check_eq "$?" 1 "portal refuses an unreadable current UKI before mutation"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" disk \
  "an unreadable current UKI leaves disk authority unchanged"
check_eq "$(test -f "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" && echo present)" present \
  "an unreadable current UKI leaves the active drop-in unchanged"
rm -f "$TMP/fail-lsinitcpio"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/unreadable-reset.error"

: >"$TMP/fail-lsinitcpio"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/portal-inspect.error"
check_eq "$?" 1 "portal does not claim convergence when UKI inspection fails"
rm -f "$TMP/fail-lsinitcpio"
PATH="$PATH_VALUE" "$CONF" machine set boot portal --secrets-stdin \
  >/dev/null 2>"$TMP/portal-secrets.error"
check_eq "$?" 2 "portal rejects the disk-only secrets option"

# Portal to disk validates all secrets first, adds passworded kids in
# byte order, installs the package template, rebuilds once, and writes disk last.
printf 'boot=portal\nparent=mark\n' >"$ETC/machine.conf"
printf 'name=Ada\npassword=set\n' >"$ETC/kids/kid-ada.conf"
printf 'name=Cy\npassword=set\n' >"$ETC/kids/kid-cy.conf"
printf 'name=Dot\npassword=none\n' >"$ETC/kids/kid-dot.conf"
chmod 0644 "$ETC/kids"/*.conf
printf '0=parentpass\n' >"$SLOT_STATE"
printf 'HOOKS=(base block encrypt filesystems)\n' >"$ROOT/etc/mkinitcpio.conf"
printf 'absent\n' >"$STATE"
printf 'editor_enabled: yes\ndefault_entry: 1\n' >"$ROOT/boot/limine.conf"
printf 'MAX_SNAPSHOT_ENTRIES=10\n' >"$ROOT/etc/default/limine"
rm -f "$ETC/luks-slots" "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
: >"$LOG"

PATH="$PATH_VALUE" "$CONF" machine set boot disk </dev/null \
  >/dev/null 2>"$TMP/noninteractive.error"
check_eq "$?" 1 "a noninteractive disk transition without secrets fails"
check_eq "$(grep -c '^cryptsetup luksAddKey ' "$LOG" 2>/dev/null || true)" 0 \
  "a noninteractive disk transition without secrets adds no slot"
: >"$LOG"

printf 'parentpass\nadapass\ncypass\n' |
  OMARCHY_KIDS_LUKS_DEVICE=/dev/hostile PATH="$PATH_VALUE" \
    "$CONF" machine set boot disk --secrets-stdin \
    >"$TMP/disk.out" 2>"$TMP/disk.error"
status=$?
transition_log="$(cat "$LOG")"
check_eq "$status" 0 "portal to disk exits 0"
check_eq "$(grep -c '^flock [0-9][0-9]*$' <<<"$transition_log")" 1 \
  "the transition acquires the shared boot-mode lock exactly once"
check_eq "$(tail -2 <<<"$transition_log")" $'stat-machine\nflock -u 9' \
  "the lock stays held through final mode readback"
if grep -qF /dev/hostile <<<"$transition_log"; then
  bad "an environment variable selected the transition device"
else
  pass "the transition ignores an environment-selected LUKS device"
fi
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" disk \
  "portal to disk writes disk only after convergence"
check_eq "$(cat "$SLOT_STATE")" $'0=parentpass\n1=adapass\n2=cypass' \
  "portal to disk assigns kid slots in byte-sorted account order"
check_eq "$(cat "$ETC/luks-slots")" $'0=mark\n1=kid-ada\n2=kid-cy' \
  "portal to disk maps every passworded kid and excludes no-password kids"
if cmp -s "$DIR/share/boot/omarchy_kids.conf" "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"; then
  pass "portal to disk installs the package-owned inactive template"
else
  bad "portal to disk did not install the package-owned template"
fi
check_eq "$(grep -c '^mkinitcpio -P$' "$LOG" 2>/dev/null || true)" 1 \
  "portal to disk rebuilds exactly once"
check_eq "$(cat "$STATE")" present "portal to disk verifies a UKI with the hook"
check_eq "$(head -1 "$ROOT/boot/limine.conf")" 'editor_enabled: no' \
  "portal to disk disables the Limine editor"
check_eq "$(grep -c '^# omarchy-kids: was editor_enabled=yes$' "$ROOT/boot/limine.conf")" 1 \
  "portal to disk records the Limine editor value it owns"
check_eq "$(cat "$ROOT/etc/default/limine")" \
  $'# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=10\nMAX_SNAPSHOT_ENTRIES=0' \
  "portal to disk records and hides Limine snapshot entries"
if grep -qE 'parentpass|adapass|cypass' "$TMP/disk.out" "$TMP/disk.error" "$LOG"; then
  bad "portal to disk exposed a secret in output or argv"
else
  pass "portal to disk exposes no secret in output or argv"
fi

: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot disk </dev/null \
  >"$TMP/disk-again.out" 2>"$TMP/disk-again.error"
check_eq "$?" 0 "a converged disk rerun needs no secrets"
check_eq "$(grep -c '^cryptsetup luksAddKey ' "$LOG" 2>/dev/null || true)" 0 \
  "a converged disk rerun adds no slot"
check_eq "$(grep -c '^mkinitcpio ' "$LOG" 2>/dev/null || true)" 0 \
  "a converged disk rerun does not rebuild"
map_inode="$(file_inode "$ETC/luks-slots")"
PATH="$PATH_VALUE" "$CONF" machine set boot disk </dev/null \
  >/dev/null 2>"$TMP/disk-third.error"
check_eq "$(file_inode "$ETC/luks-slots")" "$map_inode" \
  "a converged disk rerun does not replace the slot map"

# Return to a clean portal fixture for failure cases.
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/reset.error"
check_eq "$(grep -c '^editor_enabled: yes$' "$ROOT/boot/limine.conf")" 1 \
  "portal restores the Limine editor value changed by disk mode"
printf '0=parentpass\n' >"$SLOT_STATE"
printf 'absent\n' >"$STATE"
rm -f "$ETC/luks-slots" "$ETC/boot-transition.recovery" \
  "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"

: >"$LOG"
printf 'parentpass\nadapass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/missing.error"
check_eq "$?" 1 "missing kid secret fails"
check_eq "$(grep -c '^cryptsetup luksAddKey ' "$LOG" 2>/dev/null || true)" 0 \
  "missing kid secret fails before a slot is added"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "missing kid secret leaves portal authoritative"

: >"$LOG"
printf 'parentpass\nadapass\ncypass\nextra\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/extra.error"
check_eq "$?" 1 "extra secret line fails"
check_eq "$(grep -c '^cryptsetup ' "$LOG" 2>/dev/null || true)" 1 \
  "extra secret line fails before any secret or slot validation beyond the initial dump"

: >"$TMP/fail-add-2"
: >"$LOG"
printf 'parentpass\nadapass\ncypass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/add-failure.error"
status=$?
rm -f "$TMP/fail-add-2"
check_eq "$status" 1 "a later slot-add failure returns nonzero"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "a later slot-add failure rolls back an earlier addition"
check_eq "$(test ! -e "$ETC/luks-slots" && echo absent)" absent \
  "a slot-add failure restores the absent portal map"
check_eq "$(test ! -e "$ETC/boot-transition.recovery" && echo absent)" absent \
  "a completed rollback removes its recovery record"
check_eq "$(test ! -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" && echo absent)" absent \
  "a slot-add failure leaves the active template absent"
check_eq "$(grep -c '^mkinitcpio ' "$LOG" 2>/dev/null || true)" 0 \
  "a slot-add failure never rebuilds"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a slot-add failure keeps portal authoritative"

: >"$TMP/fail-mkinitcpio-once"
: >"$LOG"
printf 'parentpass\nadapass\ncypass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/rebuild-failure.error"
status=$?
check_eq "$status" 1 "a failed disk rebuild returns nonzero"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "a failed disk rebuild rolls back every added slot"
check_eq "$(test ! -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" && echo absent)" absent \
  "a failed disk rebuild removes the active template"
check_eq "$(cat "$STATE")" absent \
  "a failed disk rebuild performs a portal cleanup rebuild"
check_eq "$(grep -c '^mkinitcpio -P$' "$LOG" 2>/dev/null || true)" 2 \
  "a partial failed rebuild is followed by one cleanup rebuild"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a failed disk rebuild keeps portal authoritative"

# Even with no kids, portal-to-disk records the prior map before replacing it.
rm -f "$ETC/kids"/*.conf "$ETC/luks-slots" "$ETC/boot-transition.recovery" \
  "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf '0=parentpass\n' >"$SLOT_STATE"
printf 'absent\n' >"$STATE"
: >"$TMP/fail-mkinitcpio-once"
printf 'parentpass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/no-kids-failure.error"
check_eq "$?" 1 "a zero-kid disk rebuild failure returns nonzero"
check_eq "$(test ! -e "$ETC/luks-slots" && echo absent)" absent \
  "a zero-kid disk rebuild failure restores the absent portal map"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a zero-kid disk rebuild failure keeps portal authoritative"

# If the setter's own readback fails after committing disk, restore portal too.
printf 'name=Ada\npassword=set\n' >"$ETC/kids/kid-ada.conf"
chmod 0644 "$ETC/kids/kid-ada.conf"
printf 'absent\n' >"$STATE"
: >"$TMP/arm-mode-readback-failure"
printf 'parentpass\nadapass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/readback-failure.error"
check_eq "$?" 1 "a failed setter readback after the disk commit returns nonzero"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a failed setter readback after the disk commit restores portal authority"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "a failed setter readback after the disk commit rolls back the added slot"
check_eq "$(test ! -e "$ETC/luks-slots" && echo absent)" absent \
  "a failed setter readback after the disk commit restores the prior map"
check_eq "$(grep -c '^editor_enabled: yes$' "$ROOT/boot/limine.conf")" 1 \
  "a failed setter readback after the disk commit restores the Limine editor"

printf 'name=Cy\npassword=set\n' >"$ETC/kids/kid-cy.conf"
printf 'name=Dot\npassword=none\n' >"$ETC/kids/kid-dot.conf"
chmod 0644 "$ETC/kids"/*.conf

# A failed slot kill leaves the complete map as the retry record. The
# rerun skips the already-absent slot, removes the rest, then rebuilds once.
printf 'boot=disk\nparent=mark\n' >"$ETC/machine.conf"
printf '0=mark\n3=kid-ada\n5=kid-cy\n' >"$ETC/luks-slots"
chmod 0600 "$ETC/luks-slots"
printf '0=parentpass\n3=adapass\n5=cypass\n' >"$SLOT_STATE"
printf 'active drop-in\n' >"$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'present\n' >"$STATE"
: >"$TMP/fail-kill-5"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/kill-failure.error"
status=$?
check_eq "$status" 1 "a failed slot removal returns nonzero"
check_eq "$(PATH="$PATH_VALUE" "$CONF" machine get boot)" portal \
  "a failed slot removal has already made portal authoritative"
check_eq "$(cat "$SLOT_STATE")" $'0=parentpass\n5=cypass' \
  "a failed slot removal preserves the unremoved slot"
check_eq "$(cat "$ETC/luks-slots")" $'0=mark\n3=kid-ada\n5=kid-cy' \
  "a failed slot removal preserves the full retry map"
check_eq "$(grep -c '^mkinitcpio ' "$LOG" 2>/dev/null || true)" 0 \
  "a failed slot removal stops before rebuilding"

rm -f "$TMP/fail-kill-5"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/kill-retry.error"
check_eq "$?" 0 "portal retry resumes after a slot-removal failure"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "portal retry removes the remaining slot without touching slot 0"
check_eq "$(test ! -e "$ETC/luks-slots" && echo absent)" absent \
  "portal retry removes the completed retry map"
check_eq "$(grep -c '^mkinitcpio -P$' "$LOG" 2>/dev/null || true)" 1 \
  "portal retry rebuilds exactly once after slot removal completes"

# An interrupted portal-to-disk attempt has one durable recovery record.
# The next run first rolls that attempt back, then starts a fresh convergence.
printf 'boot=portal\nparent=mark\n' >"$ETC/machine.conf"
printf '0=parentpass\n1=adapass\n' >"$SLOT_STATE"
rm -f "$ETC/luks-slots" "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'version=1\nmap=absent\nadd=1=kid-ada\nadd=2=kid-cy\n' \
  >"$ETC/boot-transition.recovery"
chmod 0600 "$ETC/boot-transition.recovery"
printf 'absent\n' >"$STATE"
: >"$LOG"
printf 'parentpass\nadapass\ncypass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/interrupted.error"
status=$?
check_eq "$status" 0 "a portal-to-disk retry recovers an interrupted attempt"
check_eq "$(cat "$SLOT_STATE")" $'0=parentpass\n1=adapass\n2=cypass' \
  "the retry removes the interrupted slot before assigning the fresh ordered slots"
check_eq "$(test ! -e "$ETC/boot-transition.recovery" && echo absent)" absent \
  "the successful retry clears its durable recovery record"

# If disk was committed before record cleanup, a same-direction retry confirms
# the recorded slots and map before removing the one stale record.
printf 'version=1\nmap=absent\nadd=1=kid-ada\nadd=2=kid-cy\n' \
  >"$ETC/boot-transition.recovery"
chmod 0600 "$ETC/boot-transition.recovery"
: >"$LOG"
PATH="$PATH_VALUE" "$CONF" machine set boot disk </dev/null \
  >/dev/null 2>"$TMP/committed-recovery.error"
check_eq "$?" 0 "disk confirms a committed single recovery record"
check_eq "$(grep -c '^cryptsetup luksAddKey ' "$LOG" 2>/dev/null || true)" 0 \
  "disk recovery does not add an already committed slot"
check_eq "$(test ! -e "$ETC/boot-transition.recovery" && echo absent)" absent \
  "disk recovery removes the confirmed single record"

# One recovery record is sufficient after an interrupted addition, including
# when the next request chooses the opposite, portal direction.
printf 'boot=portal\nparent=mark\n' >"$ETC/machine.conf"
printf '0=parentpass\n1=adapass\n' >"$SLOT_STATE"
rm -f "$ETC/luks-slots" "$ETC/boot-transition.recovery" \
  "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
printf 'version=1\nmap=absent\nadd=1=kid-ada\nadd=2=kid-cy\n' \
  >"$ETC/boot-transition.recovery"
chmod 0600 "$ETC/boot-transition.recovery"
printf 'absent\n' >"$STATE"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/single-recovery.error"
check_eq "$?" 0 "portal recovers from the single interrupted-addition record"
check_eq "$(cat "$SLOT_STATE")" '0=parentpass' \
  "portal recovery removes the slot named by the single record"
check_eq "$(test ! -e "$ETC/boot-transition.recovery" && echo absent)" absent \
  "portal recovery removes the completed single record"

# Disk records a previously absent Limine setting so portal removes only
# the snapshot state introduced by the transition.
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/absent-marker-reset.error"
rm -f "$ETC/kids"/*.conf
printf '0=parentpass\n' >"$SLOT_STATE"
printf 'KEEP=yes\n' >"$ROOT/etc/default/limine"
printf 'absent\n' >"$STATE"
printf 'parentpass\n' |
  PATH="$PATH_VALUE" "$CONF" machine set boot disk --secrets-stdin \
    >/dev/null 2>"$TMP/absent-marker-disk.error"
check_eq "$?" 0 "disk convergence records an absent Limine snapshot setting"
check_eq "$(cat "$ROOT/etc/default/limine")" \
  $'KEEP=yes\n# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=\nMAX_SNAPSHOT_ENTRIES=0' \
  "disk records that the Limine snapshot setting was absent"
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/absent-marker-portal.error"
check_eq "$?" 0 "portal convergence restores an absent Limine snapshot setting"
check_eq "$(cat "$ROOT/etc/default/limine")" 'KEEP=yes' \
  "portal removes the snapshot setting that disk introduced"

# The installed root path must not depend on HOME or other ambient values.
PATH="$PATH_VALUE" "$CONF" machine set boot portal >/dev/null 2>"$TMP/env-reset.error"
: >"$LOG"
env -i PATH="$PATH_VALUE" "$CONF" machine set boot portal \
  >/dev/null 2>"$TMP/env-empty.error"
check_eq "$?" 0 "a root transition works with env -i and no HOME"

echo "boot-mode-test RESULT: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
