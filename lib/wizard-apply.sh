# shellcheck shell=bash
# lib/wizard-apply.sh -- omarchy-kids-wizard's Apply screen (A13b) and its
# five steps: getok, account, web, pkgs, safety, then Done (A14). Sourced
# by the dispatcher; not meant to be executed directly. See docs/wizard.md
# "Apply's five steps" for the exit-code/logging contract each step follows.

# Step 1: the one sudo prompt for the whole run; writes machine.conf's
# parent= first (issue #46 -- authd needs it before anything else runs).
apply_step_getok() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  [dry-run] sudo -v\n'
        printf '  [dry-run] sudo %q machine set parent %q\n' "$CONF_BIN" "$INVOKING_USER"
        printf '  [dry-run] sudo systemctl enable --now'
        printf ' %q' "${KIDS_UNITS[@]}" "${KIDS_SOCKETS[@]}" "${KIDS_TIMERS[@]}"
        printf '\n'
        printf '  [dry-run] sudo install -d -m 0755 %q\n' "$(dirname "$SETUP_LOG")"
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        printf '%s\n' "$PARENT_PASSWORD" | sudo -S -p '' -v 2>/dev/null || return 1
    fi
    sudo "$CONF_BIN" machine set parent "$INVOKING_USER" || return 1
    sudo systemctl enable --now "${KIDS_UNITS[@]}" "${KIDS_SOCKETS[@]}" "${KIDS_TIMERS[@]}" || return 1
    sudo install -d -m 0755 "$(dirname "$SETUP_LOG")"
}

# Step 2: the account, plus every Appendix B override (R-BAND-2). A
# failed override doesn't stop the rest, so a parent sees every problem
# at once rather than one at a time across re-runs.
apply_step_account() {
    local rc=0
    if ((NO_PASSWORD)); then
        run_priv_stdin "$PROVISION_BIN" add "$DISPLAY_NAME" --band "$BAND" --avatar "$AVATAR" --no-password --apply </dev/null
    else
        printf '%s\n%s\n' "$KID_PASSWORD" "$PARENT_PASSWORD" |
            run_priv_stdin "$PROVISION_BIN" add "$DISPLAY_NAME" --band "$BAND" --avatar "$AVATAR" --password-stdin --parent-password-stdin --apply
    fi
    rc=$?
    ((rc == 0)) || return "$rc"

    maybe_override level "$LEVEL" "$(band_field "$BAND" level)" || rc=$?
    maybe_override web "$WEB_MODE" "$(band_field "$BAND" web)" || rc=$?
    maybe_override wifi "$WIFI_MODE" "$(band_field "$BAND" wifi)" || rc=$?
    maybe_override budget_min "$BUDGET_MIN" "$(band_field "$BAND" budget_min)" || rc=$?
    maybe_override lights_out "$LIGHTS_OUT" "$(band_field "$BAND" lights_out)" || rc=$?
    maybe_override allowlist "$ALLOWLIST_IDS" "$(pack_field "$BAND" id | paste -sd, -)" || rc=$?
    maybe_override dns "$DNS_MODE" "$(band_field "$BAND" dns)" || rc=$?
    maybe_override sites "$SITES" "$(pack_sites "$BAND")" || rc=$?
    maybe_override menu "$MENU_MODE" "$(band_field "$BAND" menu)" || rc=$?
    maybe_override history_visible "$HISTORY_VISIBLE" "$(band_field "$BAND" history_visible)" || rc=$?
    maybe_override budget_min_weekend "$BUDGET_MIN_WEEKEND" "$(band_field "$BAND" budget_min_weekend)" || rc=$?
    maybe_override lights_out_weekend "$LIGHTS_OUT_WEEKEND" "$(band_field "$BAND" lights_out_weekend)" || rc=$?
    # theme's default is the parent's own current theme, not a band value
    # (docs/theming.md) -- $PROVISION_BIN's theme step already copied it.
    maybe_override theme "$THEME" "$(theme_current_name)" || rc=$?
    return "$rc"
}

# Step 3: web policy.
apply_step_web() {
    run_priv "$WEB_BIN" install "$BAND" --apply
}

# Step 4: starter pack via omarchy-kids-apps --now, synchronous so the
# checkmark means the packages are really in. Always the whole band pack;
# the allowlist apply_step_account writes is what restricts the launcher.
apply_step_pkgs() {
    run_priv "$APPS_BIN" install "$BAND" --now --apply
}

# Step 5: the safety check (A13c) -- see docs/wizard.md "The safety check".
apply_step_safety() {
    local rc=0
    run_priv "$ASSERT_BIN"
    rc=$?
    if [[ "$DRY_RUN" == "1" ]] || id "$ACCOUNT" >/dev/null 2>&1; then
        run_priv_as "$ACCOUNT" "$SESSION_BIN" --check
        local session_rc=$?
        ((session_rc == 0)) || rc=$session_rc
    else
        echo "  (skipping the session check — account $ACCOUNT does not exist)"
        rc=1
    fi
    return "$rc"
}

# run_apply_step LABEL FUNC — runs FUNC, tees its output live and (a real
# run only) to $SETUP_LOG (R-WIZ-5). FUNC's own exit code, via
# PIPESTATUS, decides ✓/✗ -- docs/wizard.md "Apply's five steps".
run_apply_step() {
    local func="$2" tmp rc
    tmp="$(mktemp)"
    if [[ "$DRY_RUN" == "1" ]]; then
        "$func" 2>&1 | tee "$tmp"
        rc="${PIPESTATUS[0]}"
    else
        "$func" 2>&1 | tee "$tmp" | sudo tee -a "$SETUP_LOG" >/dev/null
        rc="${PIPESTATUS[0]}"
    fi
    if ((rc != 0)); then
        echo
        echo "\"$1\" failed. Last lines:"
        tail -n 10 "$tmp"
    fi
    rm -f "$tmp"
    return "$rc"
}

# A13b/A13c: Apply, then the safety check. Stops at the first failing
# step (real run only) rather than reporting success for a step that
# changed nothing -- docs/wizard.md "Apply's five steps".
screen_apply() {
    tui_header "Apply" 14 "$TOTAL_STEPS" 0 ""
    echo

    # shellcheck disable=SC2034 # read by tui_progress via nameref-by-name
    local steps=(
        "Getting your OK"
        "Setting up $DISPLAY_NAME's account"
        "Turning on the safe browser rules"
        "Installing $BAND starter apps"
        "Double-checking everything is safe"
    )
    local -a funcs=(apply_step_getok apply_step_account apply_step_web apply_step_pkgs apply_step_safety)
    local total=${#steps[@]} i rc k

    tui_progress steps 0 "You can watch this happen — nothing here needs another click."

    APPLY_OK=1
    for ((i = 0; i < total; i++)); do
        run_apply_step "${steps[i]}" "${funcs[i]}"
        rc=$?
        if [[ "$DRY_RUN" != "1" ]] && ((rc != 0)); then
            APPLY_OK=0
            for ((k = 0; k < total; k++)); do
                if ((k < i)); then
                    echo "  ✓ ${steps[k]}"
                elif ((k == i)); then
                    echo "  ✗ ${steps[k]}"
                else
                    echo "  · ${steps[k]}"
                fi
            done
            FAILED_STEP="${steps[i]}"
            return 0
        fi
        if ((i == total - 1)); then
            tui_progress steps $((i + 1)) "The technical log is at $SETUP_LOG."
        else
            tui_progress steps $((i + 1))
        fi
    done
    return 0
}

# A14: Done. Two buttons, no third choice -- issue #37's "Show kids in my
# bar?" prompt would break every answers_file(...) test, so Omy's line
# mentions omarchy-kids-bar instead (AGENTS.md: spec wins).
screen_done() {
    local headline
    if ((APPLY_OK)); then
        headline="$DISPLAY_NAME's desktop is ready."
    else
        headline="Setup stopped at \"$FAILED_STEP\" — see the lines above for what went wrong."
    fi
    local omy="$headline Next time the computer starts, $DISPLAY_NAME can just type their password."
    if ((APPLY_OK)); then
        omy+=" Want a peek at $DISPLAY_NAME from your own bar? Run 'omarchy-kids-bar enable' any time — it only changes what you ask it to."
    fi
    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=(
        "parent|Return to my desktop|"
        "kid|Open $DISPLAY_NAME's desktop|"
    )
    tui_screen_choose "Done" 15 "$TOTAL_STEPS" 1 "$omy" choices "parent"
    local rc=$?
    if [[ "$TUI_REPLY" == kid ]]; then
        echo
        echo "There's no live preview switch yet on this box (see docs/wizard.md) —"
        echo "$DISPLAY_NAME logs in from the portal next time the screen locks or the computer starts."
    fi
    return $((rc == 130 ? 130 : 0))
}

