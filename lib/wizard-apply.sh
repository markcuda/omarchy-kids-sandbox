# shellcheck shell=bash
# lib/wizard-apply.sh — omarchy-kids-wizard's Apply screen (A13b) and its
# five steps: getok, account, web, pkgs, safety, then Done (A14). Sourced
# by the dispatcher; not meant to be executed directly.

# --- Apply's five steps, one function each -------------------------------
# Each prints/runs its own commands (via run_priv/run_priv_stdin/run_priv_as,
# every one of which gets an explicit --apply where that command's own
# convention needs it — DRY_RUN never crosses `sudo` into a child process,
# so the flag on argv is the only thing that actually turns a real run on;
# see docs/wizard.md "Root and the one sudo prompt") and returns that
# command's real exit code, which run_apply_step below both displays and
# uses to decide whether to keep going.

# Step 1: the one sudo prompt for the whole Apply step. Writes
# machine.conf's parent=$INVOKING_USER first (before anything that needs
# it, issue #46 -- without it, authd answers "no" to every password and
# provision refuses to add a kid), enables the package's units
# (lib/units.sh, same list omarchy-kids-assert's "units" lock uses), then
# ensures the technical log's directory exists.
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

# Step 2: the account itself, plus every A7/A10/A11 choice that differs
# from the band default (R-BAND-2: only overrides are ever written). A
# failed override still fails the step — none of these are optional once
# chosen — but doesn't stop the others from being attempted, so a parent
# sees every problem at once rather than one at a time across re-runs.
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

    # Every Appendix B cell either path can change — Simple's own five
    # (A7/A8/A10/A11's web/budget_min/lights_out/wifi/level) plus the
    # seven Advanced's checklist adds (issue #20) — through the same
    # maybe_override, which only ever writes the ones that actually
    # differ from this band's default (R-BAND-2: "the profile stores
    # only overrides"). A kid set up entirely through Simple never
    # touches the last seven, so they're always still at their band
    # default here and none of these seven ever fire for one.
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
    return "$rc"
}

# Step 3: web policy.
apply_step_web() {
    run_priv "$WEB_BIN" install "$BAND" --apply
}

# Step 4: starter pack via omarchy-kids-apps --now (R-WIZ-4/R-APPS-3):
# synchronous, so the on-screen checkmark means the packages are really
# in. Always installs the whole band pack regardless of A9's "let me
# pick" -- the allowlist apply_step_account writes is what actually
# restricts the kid's launcher, so this is correct, not a bug.
apply_step_pkgs() {
    run_priv "$APPS_BIN" install "$BAND" --now --apply
}

# Step 5: the safety check (A13c) -- omarchy-kids-assert (I-4), then the
# same R-DESK-2 preflight as the new kid's own account, skipped with a
# clear line if that account doesn't actually exist yet. Not swapped for
# one `omarchy-kids-check --json` call: check is read-only (a FAIL there
# means "run assert"), and --json isn't this screen's human table. See
# docs/check.md's "Judgment calls".
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

# run_apply_step LABEL FUNC — runs FUNC (one of the apply_step_* above),
# showing its output live and, in a real run, also appending it to
# $SETUP_LOG (R-WIZ-5) via `sudo tee -a` — a parent's own unprivileged
# wizard process can't append to that root-owned file directly, so the
# write itself has to go through sudo too, same as every other Apply
# command. A --dry-run never touches the log. FUNC's own real exit code
# (not tee's) decides ✓ or ✗, via bash's PIPESTATUS, regardless of
# whether pipefail happens to be set.
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

# A13b/A13c: Apply, then the safety check. The parent password was
# already collected and (where possible) verified at A2 — see
# screen_parent_password and docs/wizard.md "Root and the one sudo prompt".
# Stops at the first failing step (real run only — --dry-run's steps
# always "succeed", there being nothing real to fail) rather than
# marching on and reporting success for a step that changed nothing.
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

# A14: Done. Exactly the Appendix A row: one Omy line, two buttons, no
# third choice -- issue #37 asked for a "Show kids in my bar?" prompt
# here, which would break every existing answers_file(...) sequence in
# test/shell.d/wizard-test.sh; per AGENTS.md ("spec wins, ticket gets a
# comment"), Omy's line mentions omarchy-kids-bar instead.
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

