# shellcheck shell=bash
# lib/wizard-screens.sh — omarchy-kids-wizard's Easy-path screens (A1-A13),
# one function per screen, Appendix A order; each returns lib/tui.sh's
# 0/1/130 contract for the driver loop to switch on. Sourced by the
# dispatcher; not meant to be executed directly.

# --- screens -------------------------------------------------------------
# One function per screen, in Appendix A order. Each returns lib/tui.sh's
# own contract: 0 = continue (answer in the variable the caller expects),
# 1 = Esc/"go back", 130 = Ctrl+C/"leave, nothing changed" (the driver
# loop below is what actually does the going-back and leaving).

# A1: Welcome.
screen_welcome() {
    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=("begin|Begin|")
    local omy=$'Hi, I\'m Omy. Kids Mode turns this computer into one your kids can use on their own.\n\nEach kid gets their own desktop, at their own level.\nYou stay in charge with one password, yours.\nEverything can be undone.'
    tui_screen_choose "Welcome" 1 "$TOTAL_STEPS" 1 "$omy" choices "begin" "$TUI_FOOTER_FIRST"
}

# A2: Parent password (SPEC.md R-WIZ-1), kept in memory only, reused at
# Apply for the sudo prompt. Verified via omarchy-kids-authd when its
# socket is active, else `sudo -S -v` with the same candidate. --dry-run
# always accepts on the first try; a real run gives three tries then
# leaves like Ctrl+C (issue #46) -- counted here, not via lib/tui.sh's
# own retry loop, since that runs the validator in a subshell. See
# docs/wizard.md.
PARENT_PASSWORD_TRIES=3
screen_parent_password() {
    local attempt=0
    while true; do
        tui_screen_input "First, your password." 2 "$TOTAL_STEPS" 0 "" \
            password "Kids Mode uses it for every grown-up decision. It's the same one you log in with."
        local rc=$?
        ((rc == 0)) || return $rc

        if [[ "$DRY_RUN" == "1" ]] || verify_parent_password "$TUI_REPLY"; then
            PARENT_PASSWORD="$TUI_REPLY"
            return 0
        fi

        attempt=$((attempt + 1))
        echo
        if ((attempt >= PARENT_PASSWORD_TRIES)); then
            echo "That wasn't it."
            return 130
        fi
        echo "That wasn't it. Try again."
    done
}

# A3: Name.
screen_name() {
    tui_screen_input "What's your kid's name?" 3 "$TOTAL_STEPS" 0 "" \
        text "First name or nickname. It's what they'll see." validate_kid_name
    local rc=$?
    ((rc == 0)) || return $rc
    DISPLAY_NAME="$TUI_REPLY"
    ACCOUNT="$("$CONF_BIN" slug "$DISPLAY_NAME")" || die "could not slug '$DISPLAY_NAME'"
    if [[ -e "$KIDS_DIR/$ACCOUNT.conf" ]]; then
        echo
        echo "That'll be close to $ACCOUNT on this computer (a number gets added if it's taken)."
    else
        echo
        echo "That'll be $ACCOUNT on this computer."
    fi
    return 0
}

# A4: Face — a keyboard list of share/avatars/*.svg (one of the twelve
# CC0 animals, Q18), same tui_screen_choose "arrows" input Appendix A
# calls for; there's no separate grid widget in lib/tui.sh, and a list is
# just as keyboard-complete.
screen_face() {
    local -a choices=()
    local f id label
    shopt -s nullglob
    for f in "$SHARE/avatars"/*.svg; do
        id="$(basename "$f" .svg)"
        label="$(tr '[:lower:]' '[:upper:]' <<<"${id:0:1}")${id:1}"
        choices+=("$id|$label|")
    done
    shopt -u nullglob
    if ((${#choices[@]} == 0)); then
        AVATAR="fox"
        return 0
    fi
    tui_screen_choose "Pick $DISPLAY_NAME's face." 4 "$TOTAL_STEPS" 0 "" choices "fox"
    local rc=$?
    ((rc == 0)) || return $rc
    AVATAR="$TUI_REPLY"
    return 0
}

# A5: Age.
screen_band() {
    local -a choices=()
    local b label blurb
    for b in "${VALID_BANDS[@]}"; do
        label="$(band_field "$b" label)"
        blurb="$(band_field "$b" blurb)"
        choices+=("$b|$label|$blurb")
    done
    tui_screen_choose "How old is $DISPLAY_NAME?" 5 "$TOTAL_STEPS" 0 "" choices "6-8"
    local rc=$?
    ((rc == 0)) || return $rc
    BAND="$TUI_REPLY"
    PASSWORD_MIN="$(band_field "$BAND" password_min)"
    # Seeds every Advanced-checklist row (lib/wizard-advanced.sh) to this
    # band's default, whether or not the parent ever opens that checklist
    # — Simple's own A7-A11 screens below still overwrite the five they
    # cover, same as always.
    adv_init
    # R-WIZ-4: prefetch starts here, in the background, and never blocks.
    start_prefetch "$BAND"
    return 0
}

# A6: Simple or Advanced. Advanced opens the grouped checklist
# (screen_advanced_checklist, lib/wizard-advanced.sh, issue #20) in place
# of Simple's five one-choice screens (A7-A11) — see the driver loop's
# own step-7 special case below for how "Done customizing" there skips
# straight to A12, and Esc there returns here instead of one step back.
screen_mode() {
    local choices=(
        "simple|Simple|A few clear choices with sensible defaults. About five minutes."
        "advanced|Advanced|Every setting on one screen."
    )
    tui_screen_choose "How do you want to set up $DISPLAY_NAME's computer?" \
        6 "$TOTAL_STEPS" 0 "" choices "simple"
    local rc=$?
    ((rc == 0)) || return $rc
    MODE="$TUI_REPLY"
    return 0
}

# A7: Web (Simple). Two options, band-appropriate (R-WEB-3's three real
# modes are none/garden/filtered; each band offers its own default plus
# the one adjacent alternative that actually makes sense for that band).
screen_web() {
    local -a choices=()
    local default
    case "$BAND" in
        3-5)
            choices=(
                "none|No browser|Simplest and safest for the youngest kids."
                "garden|Only sites you choose|A short list you can grow, if you'd rather start early."
            )
            default="none"
            ;;
        13+)
            choices=(
                "filtered|Filtered open web|Adult content blocked, safe search on."
                "garden|Only sites you choose|A shorter, safer list if you'd rather start there."
            )
            default="filtered"
            ;;
        *)
            choices=(
                "garden|Only sites you choose|A short list you can grow. Best for younger kids."
                "filtered|Filtered open web|Adult content blocked, safe search on."
            )
            default="garden"
            ;;
    esac
    tui_screen_choose "What can $DISPLAY_NAME see on the web?" 7 "$TOTAL_STEPS" 0 "" choices "$default"
    local rc=$?
    ((rc == 0)) || return $rc
    WEB_MODE="$TUI_REPLY"
    return 0
}

# A8: Time (Simple). B leads to two custom fields, per Appendix A.
screen_time() {
    local band_budget band_lights
    band_budget="$(band_field "$BAND" budget_min)"
    band_lights="$(band_field "$BAND" lights_out)"
    local choices=(
        "default|$band_budget minutes a day, lights out at $band_lights|Matches Ages $BAND's usual day."
        "custom|I'll set my own|Pick your own minutes and bedtime."
    )
    tui_screen_choose "How much screen time?" 8 "$TOTAL_STEPS" 0 "" choices "default"
    local rc=$?
    ((rc == 0)) || return $rc
    if [[ "$TUI_REPLY" == default ]]; then
        BUDGET_MIN="$band_budget"
        LIGHTS_OUT="$band_lights"
        return 0
    fi
    tui_screen_input "How many minutes a day?" 8 "$TOTAL_STEPS" 0 "" \
        text "A number, like 60." validate_budget_minutes
    rc=$?
    ((rc == 0)) || return $rc
    BUDGET_MIN="$TUI_REPLY"
    tui_screen_input "Lights out at?" 8 "$TOTAL_STEPS" 0 "" \
        text "24-hour time, like 19:30." validate_lights_out
    rc=$?
    ((rc == 0)) || return $rc
    LIGHTS_OUT="$TUI_REPLY"
    return 0
}

# A9: Apps (Simple). B walks the pack one app at a time via apps_pick_walk
# (above) — a confirm per app, since lib/tui.sh has no multi-select
# checklist widget yet (the real checklist is Advanced's, A13a, issue
# #20, which reuses this same walk for its own apps row).
screen_apps() {
    local names
    names="$(pack_field "$BAND" label | paste -sd, - | sed 's/,/, /g')"
    local choices=(
        "pack|The $BAND starter pack|$names"
        "pick|Let me pick|Turn any of them off, one at a time."
    )
    tui_screen_choose "Which apps to start with?" 9 "$TOTAL_STEPS" 0 "" choices "pack"
    local rc=$?
    ((rc == 0)) || return $rc
    APPS_MODE="$TUI_REPLY"
    if [[ "$APPS_MODE" == pick ]]; then
        apps_pick_walk 9 "$TOTAL_STEPS"
        rc=$?
        ((rc == 130)) && return 130
        ALLOWLIST_IDS="$TUI_REPLY"
    else
        # "The whole starter pack" — the band default, every id, in pack
        # order (R-WIZ-4's own words apply here too: re-visiting this
        # screen after an earlier "Let me pick" must not leave a stale
        # partial selection behind).
        ALLOWLIST_IDS="$(pack_field "$BAND" id | paste -sd, -)"
    fi
    return 0
}

# A10: Wi-Fi (Simple).
screen_wifi() {
    local default
    default="$(band_field "$BAND" wifi)"
    local choices=(
        "parent|Ask me first|Wi-Fi requests go through you."
        "helper|On their own, safely|They can join school or café Wi-Fi. The network can't change what's blocked."
    )
    tui_screen_choose "Can $DISPLAY_NAME join new Wi-Fi?" 10 "$TOTAL_STEPS" 0 "" choices "$default"
    local rc=$?
    ((rc == 0)) || return $rc
    WIFI_MODE="$TUI_REPLY"
    return 0
}

# A11: Level (Simple), band default marked.
screen_level() {
    local default
    default="$(band_field "$BAND" level)"
    local choices=(
        "1|One thing at a time|Simplest — one app fills the screen."
        "2|Two things side by side|Split-screen multitasking."
        "3|The full desktop|Everything Omarchy normally offers."
    )
    tui_screen_choose "How should $DISPLAY_NAME's desktop work?" 11 "$TOTAL_STEPS" 0 "" choices "$default"
    local rc=$?
    ((rc == 0)) || return $rc
    LEVEL="$TUI_REPLY"
    return 0
}

# A12: Kid password. 3-5 gets an extra "set one or not" choice first
# (R-BAND's password_optional).
screen_password() {
    NO_PASSWORD=0
    if [[ "$BAND" == "3-5" ]]; then
        local choices=(
            "yes|Set a password|$DISPLAY_NAME types it to get in."
            "no|No password|$DISPLAY_NAME gets in once you start their session, no typing needed."
        )
        tui_screen_choose "Give $DISPLAY_NAME a password?" 12 "$TOTAL_STEPS" 0 "" choices "yes"
        local rc=$?
        ((rc == 0)) || return $rc
        if [[ "$TUI_REPLY" == no ]]; then
            NO_PASSWORD=1
            KID_PASSWORD=""
            return 0
        fi
    fi

    while true; do
        tui_screen_input "Now a password for $DISPLAY_NAME." 12 "$TOTAL_STEPS" 0 "" \
            password "This unlocks $DISPLAY_NAME's screen (and this computer's disk, if it's encrypted) and logs them in." \
            validate_kid_password
        local rc=$?
        ((rc == 0)) || return $rc
        local first="$TUI_REPLY"

        tui_screen_input "Type it again to be sure." 12 "$TOTAL_STEPS" 0 "" \
            password "Same password, once more." validate_kid_password
        rc=$?
        ((rc == 0)) || return $rc

        if [[ "$first" == "$TUI_REPLY" ]]; then
            KID_PASSWORD="$first"
            return 0
        fi
        echo
        echo "Those didn't match — let's try again."
    done
}

# A13: Summary. "Change something" opens the same grouped checklist
# Advanced uses (screen_advanced_checklist, lib/wizard-advanced.sh, issue
# #20, point 2), for a kid set up either way, then redraws this same
# summary with whatever changed — so this is a loop, not a single screen.
screen_summary() {
    while true; do
        local label blurb apps_desc password_line
        label="$(band_field "$BAND" label)"
        blurb="$(band_field "$BAND" blurb)"
        apps_desc="$(friendly_allowlist "$ALLOWLIST_IDS")"
        if ((NO_PASSWORD)); then
            password_line="No password — $DISPLAY_NAME gets in once you start their session."
        else
            password_line="$DISPLAY_NAME types their own password to get in."
        fi

        # shellcheck disable=SC2034 # read by tui_screen_summary via nameref-by-name
        local rows=(
            "Account|$ACCOUNT"
            "Face|$AVATAR"
            "Age band|$label ($blurb)"
            "Desktop|$(mark_if_changed level "Level $LEVEL")"
            "Web|$(mark_if_changed web "$(friendly_web_mode "$WEB_MODE")")"
            "Screen time|$(mark_if_changed budget_min "$BUDGET_MIN minutes a day")"
            "Bedtime|$(mark_if_changed lights_out "$LIGHTS_OUT")"
            "Wi-Fi|$(mark_if_changed wifi "$(friendly_wifi_mode "$WIFI_MODE")")"
            "Starter apps|$(mark_if_changed allowlist "$apps_desc")"
            "Password|$password_line"
        )
        # The seven cells Simple never shows on its own (dns, sites, menu,
        # history_visible, and the two weekend fields) only appear here
        # once Advanced (or this same "Change something") has actually
        # changed one — a Simple-only kid's summary looks exactly as it
        # always has.
        adv_summary_extra_rows rows
        tui_screen_summary "Here's what happens next for $DISPLAY_NAME." 13 "$TOTAL_STEPS" 0 "" rows

        local choices=("apply|Apply|" "change|Change something|")
        tui_screen_choose "Ready?" 13 "$TOTAL_STEPS" 0 "" choices "apply"
        local rc=$?
        ((rc == 0)) || return $rc # Esc/Ctrl+C: go back a screen / leave
        [[ "$TUI_REPLY" == apply ]] && return 0

        screen_advanced_checklist 13 "$TOTAL_STEPS"
        rc=$?
        ((rc == 130)) && return 130
        # rc 0 ("Done customizing") or 1 (Esc out of the checklist's own
        # row list): either way, back to a freshly recomputed summary.
    done
}
