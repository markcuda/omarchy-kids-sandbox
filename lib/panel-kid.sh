# shellcheck shell=bash
# lib/panel-kid.sh — omarchy-kids-panel's P2 (one kid): time, web, apps,
# plugins, data, desktop (level, theme — issue #53), password, remove —
# screen_kid is the row menu that dispatches to each. Sourced by the
# dispatcher; not meant to be executed directly.

# --- P2: one kid -------------------------------------------------------------

screen_kid_time() { # ACCOUNT NAME
    local account="$1" name="$2"
    while true; do
        local status_out budget lights
        status_out="$("$TIME_BIN" status "$account" 2>&1)"
        budget="$(kid_conf_get "$account" budget_min)"
        lights="$(kid_conf_get "$account" lights_out)"
        echo
        printf '%s\n' "$status_out"

        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local choices=(
            "grant|Give more minutes today|"
            "budget|Change today's daily budget (now $budget min)|"
            "lights|Change lights-out time (now $lights)|"
            "back|Back|"
        )
        tui_screen_choose "$name's screen time" 1 1 0 "" choices "grant"
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0

        case "$TUI_REPLY" in
            grant)
                tui_screen_input "How many more minutes today?" 1 1 0 "" \
                    text "A number, like 15." validate_positive_minutes
                rc=$?
                ((rc == 130)) && return 130
                ((rc == 0)) && run_priv "$TIME_BIN" grant "$account" "$TUI_REPLY"
                ;;
            budget)
                tui_screen_input "How many minutes a day?" 1 1 0 "" \
                    text "A number, 1 to 1440." validate_budget_minutes
                rc=$?
                ((rc == 130)) && return 130
                ((rc == 0)) && run_priv "$CONF_BIN" set "$account" budget_min "$TUI_REPLY"
                ;;
            lights)
                tui_screen_input "Lights out at?" 1 1 0 "" \
                    text "24-hour time, like 19:30." validate_lights_out
                rc=$?
                ((rc == 130)) && return 130
                ((rc == 0)) && run_priv "$CONF_BIN" set "$account" lights_out "$TUI_REPLY"
                ;;
            back) return 0 ;;
        esac
    done
}

screen_kid_web() { # ACCOUNT NAME
    local account="$1" name="$2" band mode allow_file
    band="$(kid_conf_get "$account" band)"
    mode="$(kid_conf_get "$account" web)"
    allow_file="$ETC/kids/$account/allow.txt"

    if [[ "$mode" != garden ]]; then
        # shellcheck disable=SC2034 # read by tui_screen_summary via nameref-by-name
        local rows=("Mode|$(friendly_web_mode "$mode")" "Editable list|No — this mode has no allow list (SPEC.md R-WEB-3)")
        tui_screen_summary "$name's web" 1 1 0 "" rows
        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local choices=("back|Back|")
        tui_screen_choose "Web" 1 1 0 "" choices "back"
        local rc=$?
        ((rc == 130)) && return 130
        return 0
    fi

    while true; do
        local -a lines=()
        if [[ -r "$allow_file" ]]; then
            local l
            while IFS= read -r l; do [[ -n "$l" ]] && lines+=("$l"); done <"$allow_file"
        fi
        echo
        echo "$name's allowed sites (mode: only sites you choose):"
        if ((${#lines[@]} == 0)); then
            echo "  (none of the kid's own yet — the band's starter list still applies)"
        else
            local l
            for l in "${lines[@]}"; do echo "  - $l"; done
        fi

        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local choices=("add|Add a site|" "remove|Remove a site|" "back|Back|")
        tui_screen_choose "Web" 1 1 0 "" choices "add"
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0

        case "$TUI_REPLY" in
            add)
                tui_screen_input "Add which site?" 1 1 0 "" \
                    text "A hostname, like example.com." validate_hostname
                rc=$?
                ((rc == 130)) && return 130
                if ((rc == 0)); then
                    lines+=("$TUI_REPLY")
                    # warm_sudo first, in *this* shell: write_root_file is the
                    # receiving end of a pipe below, so it runs in a subshell
                    # that can't set our SUDO_WARMED flag back here — without
                    # this, the "one warm-up prompt" would print twice.
                    warm_sudo || continue
                    printf '%s\n' "${lines[@]}" | write_root_file "$allow_file"
                    run_priv "$WEB_BIN" install "$band" --allow "$allow_file" --apply
                fi
                ;;
            remove)
                if ((${#lines[@]} == 0)); then
                    echo "Nothing to remove yet."
                    continue
                fi
                local -a rchoices=()
                local site
                for site in "${lines[@]}"; do rchoices+=("$site|$site|"); done
                rchoices+=("back|Never mind|")
                tui_screen_choose "Remove which site?" 1 1 0 "" rchoices "back"
                rc=$?
                ((rc == 130)) && return 130
                if ((rc == 0)) && [[ "$TUI_REPLY" != back ]]; then
                    local -a kept=()
                    for site in "${lines[@]}"; do [[ "$site" != "$TUI_REPLY" ]] && kept+=("$site"); done
                    warm_sudo || continue
                    if ((${#kept[@]} == 0)); then
                        write_root_file "$allow_file" </dev/null
                    else
                        printf '%s\n' "${kept[@]}" | write_root_file "$allow_file"
                    fi
                    run_priv "$WEB_BIN" install "$band" --allow "$allow_file" --apply
                fi
                ;;
            back) return 0 ;;
        esac
    done
}

screen_kid_apps() { # ACCOUNT NAME
    local account="$1" name="$2"
    while true; do
        local list_out allow
        list_out="$("$APPS_BIN" list "$account" 2>/dev/null)" || {
            echo "Could not read $name's app pack."
            return 0
        }
        allow="$("$APPS_BIN" allowlist "$account" 2>/dev/null)"

        local -a choices=()
        local first=1 line id label
        while IFS= read -r line; do
            if ((first)); then
                first=0
                continue
            fi
            [[ -z "$line" ]] && continue
            id="$(awk '{print $1}' <<<"$line")"
            label="$(cut -c18-41 <<<"$line" | sed 's/[[:space:]]*$//')"
            if is_in_csv "$id" "$allow"; then
                choices+=("$id|$label (shown)|")
            else
                choices+=("$id|$label (hidden)|")
            fi
        done <<<"$list_out"
        choices+=("plugins|Plugins shelf|Marketplace plugins, category Kids, verified only")
        choices+=("back|Back|")

        tui_screen_choose "$name's apps — Enter toggles" 1 1 0 "" choices "back"
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0
        case "$TUI_REPLY" in
            back) return 0 ;;
            plugins)
                screen_kid_plugins "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            *)
                if is_in_csv "$TUI_REPLY" "$allow"; then
                    run_priv "$APPS_BIN" hide "$account" "$TUI_REPLY"
                else
                    run_priv "$APPS_BIN" show "$account" "$TUI_REPLY"
                fi
                ;;
        esac
    done
}

# screen_kid_plugins ACCOUNT NAME — the "Plugins shelf" row under Apps
# (SPEC.md R-APPS-7, issue #28): marketplace listings, category Kids,
# verified only (never --all -- I-6, only what Enter can install shows).
# Enter installs for this kid, same sudo path as every other write.
# Parses shelf's table the same way screen_kid_apps parses `apps list`'s.
screen_kid_plugins() { # ACCOUNT NAME
    local account="$1" name="$2" band
    band="$(kid_conf_get "$account" band)"
    while true; do
        local shelf_out
        shelf_out="$("$PLUGINS_BIN" shelf --band "$band" 2>/dev/null)" || true

        local -a choices=()
        local first=1 line id label desc
        while IFS= read -r line; do
            if ((first)); then
                first=0
                continue
            fi
            [[ -z "$line" || "$line" == omarchy-kids-plugins:* ]] && continue
            id="$(awk '{print $1}' <<<"$line")"
            [[ -n "$id" ]] || continue
            label="$(cut -c26-49 <<<"$line" | sed 's/[[:space:]]*$//')"
            desc="$(cut -c69- <<<"$line" 2>/dev/null || true)"
            choices+=("$id|$label|$desc")
        done <<<"$shelf_out"

        if ((${#choices[@]} == 0)); then
            echo
            echo "Nothing on the Kids shelf yet for $name's band ($band)."
            # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
            local -a empty_choices=("back|Back|")
            tui_screen_choose "Plugins shelf" 1 1 0 "" empty_choices "back"
            local rc=$?
            ((rc == 130)) && return 130
            return 0
        fi
        choices+=("back|Back|")

        tui_screen_choose "$name's plugins shelf — Enter installs" 1 1 0 "" choices "back"
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0
        [[ "$TUI_REPLY" == back ]] && return 0

        run_priv "$PLUGINS_BIN" install "$TUI_REPLY" --kid "$account" --apply
    done
}

# screen_kid_data ACCOUNT NAME — R-DATA-1..5's transparency screen:
# today's/this week's minutes/launches/sites, read-only (issue #27).
# Sites needs root (a kid's Chromium profile is in a home the parent
# can't reach) unless history_visible=no, which omarchy-kids-data
# already says in plain words without root (R-DATA-4).
screen_kid_data() { # ACCOUNT NAME
    local account="$1" name="$2" hv
    hv="$(kid_conf_get "$account" history_visible)"
    echo
    echo "$name's data — today"
    if [[ "$hv" == yes ]]; then
        read_priv "$DATA_BIN" summary "$account"
    else
        "$DATA_BIN" summary "$account"
    fi
    echo
    echo "$name's data — this week"
    if [[ "$hv" == yes ]]; then
        read_priv "$DATA_BIN" summary "$account" --week
    else
        "$DATA_BIN" summary "$account" --week
    fi

    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=("back|Back|")
    tui_screen_choose "$name's data" 1 1 0 "" choices "back"
    local rc=$?
    ((rc == 130)) && return 130
    return 0
}

screen_kid_level() { # ACCOUNT NAME
    local account="$1" name="$2" current
    current="$(kid_conf_get "$account" level)"
    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=(
        "1|One thing at a time|Simplest — one app fills the screen."
        "2|Two things side by side|Split-screen multitasking."
        "3|The full desktop|Everything Omarchy normally offers."
    )
    tui_screen_choose "$name's desktop level" 1 1 0 "" choices "$current"
    local rc=$?
    ((rc == 130)) && return 130
    ((rc == 0)) || return 0
    [[ "$TUI_REPLY" != "$current" ]] && run_priv "$CONF_BIN" set "$account" level "$TUI_REPLY"
    return 0
}

# screen_kid_theme ACCOUNT NAME — a picker over theme_list_installed's own
# names (lib/theme.sh, issue #53: the system themes dir only, never a
# kid- or parent-installed one — theme_apply_for's own header has why).
# Writing an override here (`omarchy-kids-conf set <kid> theme <name>`)
# is what actually applies the theme to disk as root and best-effort
# reloads a live session — see that command's own cmd_set.
screen_kid_theme() { # ACCOUNT NAME
    local account="$1" name="$2" current
    current="$(kid_conf_get "$account" theme)"
    local -a choices=()
    local t
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        choices+=("$t|$t|")
    done < <(theme_list_installed)
    if ((${#choices[@]} == 0)); then
        echo
        echo "No installed themes found under \$OMARCHY_PATH/themes — nothing to pick from."
        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local back_choices=("back|Back|")
        tui_screen_choose "$name's theme" 1 1 0 "" back_choices "back"
        local rc=$?
        ((rc == 130)) && return 130
        return 0
    fi
    tui_screen_choose "$name's theme" 1 1 0 "" choices "$current"
    local rc=$?
    ((rc == 130)) && return 130
    ((rc == 0)) || return 0
    [[ "$TUI_REPLY" != "$current" ]] && run_priv "$CONF_BIN" set "$account" theme "$TUI_REPLY"
    return 0
}

# screen_kid_desktop ACCOUNT NAME — the panel's Desktop screen (issue
# #53's own brief: "a row in the panel's Desktop screen"): Desktop level
# and Theme, each opening its own picker above.
screen_kid_desktop() { # ACCOUNT NAME
    local account="$1" name="$2"
    while true; do
        local level_cur theme_cur
        level_cur="$(kid_conf_get "$account" level)"
        theme_cur="$(kid_conf_get "$account" theme)"
        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local choices=(
            "level|Desktop level|Level $level_cur"
            "theme|Theme|${theme_cur:-(none set)}"
            "back|Back|"
        )
        tui_screen_choose "$name's desktop" 1 1 0 "" choices "level"
        local rc=$?
        case "$rc" in
            130) return 130 ;;
            1) return 0 ;;
        esac
        ((rc == 0)) || return 0
        case "$TUI_REPLY" in
            level)
                screen_kid_level "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            theme)
                screen_kid_theme "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            back) return 0 ;;
        esac
    done
}

# screen_kid_password ACCOUNT NAME — SPEC.md R-WIZ-8's "reset password"
# has no real implementation yet (`omarchy-kids-provision` has no
# `passwd` subcommand today, only `add`/`remove`/`list` — see
# docs/provision.md); this checks for one anyway (future-proofing, per
# the issue brief) and otherwise names the exact command a parent runs
# themselves (I-6: don't claim a control that isn't there).
screen_kid_password() { # ACCOUNT NAME
    local account="$1" name="$2"
    if "$PROVISION_BIN" --help 2>&1 | grep -qE '^ *passwd\b'; then
        tui_screen_input "New password for $name" 1 1 0 "" \
            password "Typed once here; never shown, never logged."
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0
        printf '%s\n' "$TUI_REPLY" | {
            warm_sudo || return 1
            if [[ "$DRY_RUN" == "1" ]]; then
                printf '  [dry-run] sudo %s passwd %s --apply\n' "$PROVISION_BIN" "$account"
                cat >/dev/null
            else
                sudo "$PROVISION_BIN" passwd "$account" --apply
            fi
        }
        return 0
    fi

    # shellcheck disable=SC2034 # read by tui_screen_summary via nameref-by-name
    local rows=("Account|$account" "Run this|sudo passwd $account")
    tui_screen_summary "Change $name's password" 1 1 0 "" rows
    echo
    echo "There's no panel button for this yet — run the line above in a terminal;"
    echo "it asks for the new password twice and never shows it on screen."
    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=("back|Back|")
    tui_screen_choose "Password" 1 1 0 "" choices "back"
    local rc=$?
    ((rc == 130)) && return 130
    return 0
}

KID_JUST_REMOVED=0
screen_kid_remove() { # ACCOUNT NAME
    local account="$1" name="$2"
    tui_screen_input "Type \"$name\" to remove this kid's account" 1 1 0 "" \
        text "Files move to ~parent/Kids Mode/$name/ (SPEC.md R-FND-6); this can't be undone from here."
    local rc=$?
    ((rc == 130)) && return 130
    ((rc == 0)) || return 0

    if [[ "$TUI_REPLY" == "$name" ]]; then
        run_priv "$PROVISION_BIN" remove "$account" --apply
        [[ "$DRY_RUN" == "0" ]] && KID_JUST_REMOVED=1
    else
        echo
        echo "That didn't match \"$name\" — nothing was removed."
    fi
    return 0
}

screen_kid() { # ACCOUNT
    local account="$1" name band
    KID_JUST_REMOVED=0
    while true; do
        name="$(kid_conf_get "$account" name)"
        band="$(kid_conf_get "$account" band)"
        local status_out nreq
        status_out="$("$TIME_BIN" status "$account" 2>&1)"
        nreq="$(count_open_requests "$account")"
        echo
        echo "$name — band $band"
        printf '%s\n' "$status_out"
        echo "Open requests: $nreq"

        # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
        local choices=(
            "time|Screen time|"
            "web|Web|"
            "apps|Apps|"
            "data|Data|"
            "desktop|Desktop|"
            "password|Password|"
            "remove|Remove this kid|"
            "back|Back|"
        )
        tui_screen_choose "$name" 1 1 0 "" choices "time"
        local rc=$?
        case "$rc" in
            130) return 130 ;;
            1) return 0 ;;
        esac
        ((rc == 0)) || return 0

        case "$TUI_REPLY" in
            time)
                screen_kid_time "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            web)
                screen_kid_web "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            apps)
                screen_kid_apps "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            data)
                screen_kid_data "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            desktop)
                screen_kid_desktop "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            password)
                screen_kid_password "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ;;
            remove)
                screen_kid_remove "$account" "$name"
                rc=$?; ((rc == 130)) && return 130
                ((KID_JUST_REMOVED)) && return 0
                ;;
            back) return 0 ;;
        esac
    done
}
