# shellcheck shell=bash
# lib/check-accounts.sh — omarchy-kids-check's Accounts section: sudoers,
# wheel/docker, band group, home noexec, GECOS. Sourced by the dispatcher
# after source_assert and the reporting helpers; not meant to be executed
# directly.

# --- Accounts ----------------------------------------------------------

account_sudoers_check() { # account_sudoers_check ACCOUNT — R-FND-3: "no sudoers entry"
    local acct="$1" root sfile sdir f any_readable=0 hit=0
    root="$(posture_root)"
    sfile="$root/etc/sudoers"
    sdir="$root/etc/sudoers.d"
    if [[ -r "$sfile" ]]; then
        any_readable=1
        grep -Eq "(^|[[:space:]])${acct}([[:space:]]|\$)" "$sfile" 2>/dev/null && hit=1
    fi
    if [[ -d "$sdir" ]]; then
        for f in "$sdir"/*; do
            [[ -e "$f" ]] || continue
            [[ -r "$f" ]] || continue
            any_readable=1
            grep -Eq "(^|[[:space:]])${acct}([[:space:]]|\$)" "$f" 2>/dev/null && hit=1
        done
    fi
    if [[ "$any_readable" == 0 ]]; then
        add_result Accounts "account:$acct:no-sudo" warn "cannot verify: /etc/sudoers and /etc/sudoers.d aren't readable here — run with sudo to check this (R-FND-3)"
    elif [[ "$hit" == 1 ]]; then
        add_result Accounts "account:$acct:no-sudo" fail "$acct has a sudoers entry — R-FND-3 says none at all"
    else
        add_result Accounts "account:$acct:no-sudo" pass "no sudoers entry found for $acct (R-FND-3)"
    fi
}

account_gecos_check() { # account_gecos_check ACCOUNT NAME
    local acct="$1" name="$2"
    if ! command -v getent >/dev/null 2>&1; then
        add_result Accounts "account:$acct:gecos" warn "cannot verify: no getent on this box"
        return
    fi
    if gecos_ok "$acct" "$name"; then
        add_result Accounts "account:$acct:gecos" pass "$acct's GECOS field matches its profile name ($name)"
    else
        add_result Accounts "account:$acct:gecos" fail "$acct's GECOS field doesn't match its profile name ($name) — the greeter would show the wrong name"
    fi
}

run_accounts_section() {
    local acct band name groups any=0
    while IFS= read -r acct; do
        [[ -n "$acct" ]] || continue
        any=1
        band="$(profile_field "$acct" band)"
        name="$(profile_field "$acct" name)"

        if id "$acct" >/dev/null 2>&1; then
            add_result Accounts "account:$acct:exists" pass "$acct exists as a Unix account"
        else
            add_result Accounts "account:$acct:exists" fail "$acct has a profile but no Unix account (R-FND-2)"
            continue
        fi

        groups="$(current_groups "$acct")"
        if ! has_group "$groups" wheel && ! has_group "$groups" docker; then
            add_result Accounts "account:$acct:no-wheel" pass "$acct is not in wheel or docker"
        else
            add_result Accounts "account:$acct:no-wheel" fail "$acct is in wheel or docker — that's a sudo grant (SPEC.md: 'no sudo grant of any kind')"
        fi

        account_sudoers_check "$acct"

        if [[ -n "$band" ]] && groups_ok "$acct" "$band"; then
            add_result Accounts "account:$acct:band-group" pass "$acct is in omarchy-kids and its band group ($band)"
        else
            add_result Accounts "account:$acct:band-group" fail "$acct is missing omarchy-kids or its band group ($band) (R-FND-2, R-DESK-1)"
        fi

        if mount_ok "$acct"; then
            add_result Accounts "account:$acct:home-noexec" pass "$acct's home is mounted noexec,nosuid,nodev right now (R-FND-2)"
        else
            add_result Accounts "account:$acct:home-noexec" fail "$acct's home is not actually mounted noexec right now — a downloaded binary would run (R-FND-2)"
        fi

        account_gecos_check "$acct" "$name"
    done < <(kids_list "$KIDS_DIR")
    [[ "$any" == 1 ]] || add_result Accounts "accounts:none" skip "no kids provisioned yet; nothing to check"
}
