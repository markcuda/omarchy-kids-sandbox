# shellcheck shell=bash
# lib/check-login.sh — omarchy-kids-check's Login section. Sourced by the
# dispatcher; not meant to be executed directly. docs/check.md.

run_login_section() {
    if sddm_theme_ok; then
        add_result Login "login:theme-dropin" pass "the portal theme is selected (zz-omarchy-kids-theme.conf, R-LOGIN)"
    else
        add_result Login "login:theme-dropin" fail "the portal theme drop-in is missing or wrong — run 'omarchy-kids-assert' (R-LOGIN)"
    fi

    local kids_count
    kids_count="$(kid_conf_count)"
    if [[ "$kids_count" == 0 ]]; then
        add_result Login "login:theme-conf-user" skip "no kids provisioned; nothing to list"
    elif portal_conf_ok; then
        add_result Login "login:theme-conf-user" pass "theme.conf.user lists all $kids_count provisioned kid(s) (R-LOGIN, issue #39)"
    else
        add_result Login "login:theme-conf-user" fail "theme.conf.user is missing a kid, or stale — run 'omarchy-kids-assert' (R-LOGIN, issue #39)"
    fi

    local acct avatar
    while IFS= read -r acct; do
        [[ -n "$acct" ]] || continue
        avatar="$(profile_field "$acct" avatar)"
        # Cosmetic only (docs/check.md's "Login" section) -- WARN, not FAIL.
        if face_ok "$acct" "$avatar"; then
            add_result Login "login:face:$acct" pass "$acct's face icon is present and matches its avatar ($avatar)"
        else
            add_result Login "login:face:$acct" warn "$acct's face icon is missing or doesn't match ($avatar) — cosmetic only; run 'omarchy-kids-assert' (issue #39)"
        fi
    done < <(kids_list "$KIDS_DIR")

    local dropin
    dropin="$(posture_sddm_conf_dir)/zz-omarchy-kids-autologin.conf"
    if [[ -f "$dropin" ]]; then
        add_result Login "login:autologin-dropin" warn "$dropin still exists — the cleanup unit removes it ~20s after the display manager starts (R-BOOT-3); stale unless this ran right after boot"
    else
        add_result Login "login:autologin-dropin" pass "the per-boot autologin drop-in is gone, as it should be outside the ~20s boot window (R-BOOT-3)"
    fi
}
