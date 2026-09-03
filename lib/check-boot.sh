# shellcheck shell=bash
# lib/check-boot.sh — omarchy-kids-check's Boot section: the unlock
# hook, luks-slots vs. the real device, the Limine editor, snapshot
# entries. Sourced by the dispatcher; not meant to be executed directly.

# --- Boot ----------------------------------------------------------------

# boot_check_unlock_hook — R-BOOT-5, wider tool chain than
# omarchy-kids-assert's own boot-hook lock: this dev box has neither
# objcopy nor lsinitcpio, so tries lsinitcpio-on-UKI, then objcopy+
# lsinitcpio, then objcopy+bsdtar, then bsdtar alone -- whichever finds
# the hook wins; none available is WARN, never a silent PASS (R-TRUST-2).
boot_check_unlock_hook() {
    local uki tool="" found=0 tried=0 tmp
    if ! uki="$(find_uki)"; then
        add_result Boot "boot:unlock-hook" warn "cannot verify: no UKI/ESP image found to inspect (set OMARCHY_KIDS_UKI, or nothing to check on this box)"
        return
    fi

    if command -v lsinitcpio >/dev/null 2>&1; then
        tried=1
        if lsinitcpio -a "$uki" 2>/dev/null | grep -q omarchy-kids-unlock; then
            tool="lsinitcpio -a"; found=1
        fi
    fi

    if [[ "$found" == 0 ]] && command -v objcopy >/dev/null 2>&1 && command -v lsinitcpio >/dev/null 2>&1; then
        tried=1
        if boot_hook_ok; then tool="objcopy+lsinitcpio"; found=1; fi
    fi

    if [[ "$found" == 0 ]] && command -v objcopy >/dev/null 2>&1 && command -v bsdtar >/dev/null 2>&1; then
        tried=1
        tmp="$(mktemp "${TMPDIR:-/tmp}/omarchy-kids-check-initrd.XXXXXX")"
        if objcopy -O binary --only-section=.initrd "$uki" "$tmp" 2>/dev/null \
            && bsdtar -tf "$tmp" 2>/dev/null | grep -q omarchy-kids-unlock; then
            tool="objcopy+bsdtar"; found=1
        fi
        rm -f "$tmp"
    fi

    if [[ "$found" == 0 ]] && command -v bsdtar >/dev/null 2>&1; then
        tried=1
        if bsdtar -tf "$uki" 2>/dev/null | grep -q omarchy-kids-unlock; then
            tool="bsdtar (direct)"; found=1
        fi
    fi

    if [[ "$found" == 1 ]]; then
        add_result Boot "boot:unlock-hook" pass "the unlock hook is in the current boot image ($uki, via $tool) (R-BOOT-5)"
    elif [[ "$tried" == 0 ]]; then
        add_result Boot "boot:unlock-hook" warn "cannot verify: none of lsinitcpio, objcopy, or bsdtar is available on this box"
    else
        add_result Boot "boot:unlock-hook" fail "the unlock hook is NOT in the current boot image ($uki) — run 'omarchy-kids-assert' to rebuild it (R-BOOT-5)"
    fi
}

# boot_check_luks_slots — "slot map consistent with cryptsetup luksDump
# slot count" (issue #29): every numeric slot named in luks-slots must
# actually be an active LUKS2 key slot on the device (R-SEC-4 — LUKS2
# reuses freed slot numbers, so a stale mapping pointing at a slot that
# was since freed and handed to someone else is exactly the failure mode
# docs/phase1/V4.md and docs/provision.md both call out). WARNs rather
# than FAILs whenever it can't get a real answer (no luks-slots file, no
# cryptsetup, no device, no dump output) — never guesses.
boot_check_luks_slots() {
    local slots_file="$ETC/luks-slots"
    if [[ ! -r "$slots_file" ]]; then
        add_result Boot "boot:luks-slots" warn "cannot verify: no $slots_file to read"
        return
    fi
    if ! command -v cryptsetup >/dev/null 2>&1; then
        add_result Boot "boot:luks-slots" warn "cannot verify: cryptsetup isn't available on this box"
        return
    fi
    local device
    if ! device="$(detect_luks_device)"; then
        add_result Boot "boot:luks-slots" warn "cannot verify: no LUKS device found (set OMARCHY_KIDS_LUKS_DEVICE)"
        return
    fi

    local mapped=() active=() line key
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        [[ "$key" =~ ^[0-9]+$ ]] && mapped+=("$key")
    done < "$slots_file"

    local dump
    dump="$(cryptsetup luksDump "$device" 2>/dev/null || true)"
    if [[ -z "$dump" ]]; then
        add_result Boot "boot:luks-slots" warn "cannot verify: 'cryptsetup luksDump $device' produced no output (not root? wrong device?)"
        return
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && active+=("$line")
    done < <(awk '
        /^Keyslots:/ {inslots=1; next}
        /^Tokens:/ {inslots=0}
        inslots && /^[[:space:]]+[0-9]+:/ { s=$1; gsub(":","",s); print s; next }
        /^Key Slot [0-9]+: ENABLED/ { print $3 }
    ' <<<"$dump")

    local missing=() m
    for m in "${mapped[@]}"; do
        array_contains "$m" "${active[@]+"${active[@]}"}" || missing+=("$m")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        add_result Boot "boot:luks-slots" pass "$device: every slot in luks-slots (${#mapped[@]}) is an active LUKS key slot (device reports ${#active[@]}) (R-SEC-4)"
    else
        add_result Boot "boot:luks-slots" fail "$device: luks-slots maps slot(s) ${missing[*]} that are NOT active on the device — a stale mapping (R-SEC-4)"
    fi
}

boot_check_editor() {
    if [[ ! -f "$(limine_conf)" ]]; then
        add_result Boot "boot:editor-disabled" warn "cannot verify: no $(limine_conf) on this box (no Limine, or a test tree)"
        return
    fi
    if limine_editor_ok; then
        add_result Boot "boot:editor-disabled" pass "$(limine_conf): editor_enabled: no (V6)"
    else
        add_result Boot "boot:editor-disabled" fail "$(limine_conf): the boot menu editor is not disabled — run 'omarchy-kids-assert' (V6)"
    fi
}

boot_check_snapshots() {
    if [[ ! -f "$(limine_default)" ]]; then
        add_result Boot "boot:snapshot-entries" warn "cannot verify: no $(limine_default) on this box (no Limine/Snapper, or a test tree)"
        return
    fi
    local mode
    mode="$(boot_snapshot_entries_mode)"
    if limine_snapshots_ok; then
        add_result Boot "boot:snapshot-entries" pass "snapshot boot entries match machine.conf's boot.snapshot_entries=$mode (V6, issue #38)"
    else
        add_result Boot "boot:snapshot-entries" fail "snapshot boot entries don't match boot.snapshot_entries=$mode — run 'omarchy-kids-assert' (V6, issue #38)"
    fi
}

run_boot_section() {
    boot_check_unlock_hook
    boot_check_luks_slots
    boot_check_editor
    boot_check_snapshots
}
