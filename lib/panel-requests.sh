# shellcheck shell=bash
# lib/panel-requests.sh — omarchy-kids-panel's P3 (Requests): list, view
# one request's detail, approve/decline through omarchy-kids-ask. Sourced
# by the dispatcher; not meant to be executed directly.

# --- P3: Requests -----------------------------------------------------------

screen_request_detail() { # ID
    local id="$1"
    local path="$QUEUE_DIR/$id.json"
    if [[ ! -f "$path" ]]; then
        echo
        echo "That request isn't there anymore."
        return 0
    fi
    local kid kind what minutes desc
    kid="$(ask_field "$path" kid)"
    kind="$(ask_field "$path" kind)"
    what="$(ask_field "$path" what)"
    minutes="$(ask_field "$path" minutes)"
    if [[ "$kind" == time ]]; then desc="$minutes more minute(s) of screen time"; else desc="$what"; fi

    # shellcheck disable=SC2034 # read by tui_screen_summary via nameref-by-name
    local rows=("Kid|$kid" "Kind|$kind" "Asked for|$desc")
    tui_screen_summary "Request from $kid" 1 1 0 "" rows

    # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
    local choices=("approve|Approve|" "decline|Decline|" "back|Back|")
    tui_screen_choose "Approve or decline?" 1 1 0 "" choices "approve"
    local rc=$?
    ((rc == 130)) && return 130
    ((rc == 0)) || return 0
    case "$TUI_REPLY" in
        approve) run_priv "$ASK_BIN" approve "$id" --apply ;;
        decline) run_priv "$ASK_BIN" decline "$id" --apply ;;
    esac
    return 0
}

screen_requests() {
    while true; do
        local rows; rows="$("$PY" "$ASK_PY" list-open "$QUEUE_DIR" 2>/dev/null)"
        if [[ -z "$rows" ]]; then
            echo
            echo "No open requests right now."
            # shellcheck disable=SC2034 # read by tui_screen_choose via nameref-by-name
            local choices=("back|Back|")
            tui_screen_choose "Requests" 1 1 0 "" choices "back"
            local rc=$?
            ((rc == 130)) && return 130
            return 0
        fi

        local -a choices=()
        local id kid kind what minutes asked_at desc age
        while IFS=$'\t' read -r id kid kind what minutes asked_at; do
            [[ -z "$id" ]] && continue
            if [[ "$kind" == time ]]; then desc="$minutes more minute(s)"; else desc="$kind: $what"; fi
            [[ "$asked_at" =~ ^[0-9]+$ ]] || asked_at=0 # never arithmetic on an unchecked field, docs/panel.md
            age="$(human_age "$(( $(date +%s) - asked_at ))")"
            choices+=("$id|$kid — $desc ($age)|")
        done <<<"$rows"
        choices+=("back|Back|")

        tui_screen_choose "Requests" 1 1 0 "" choices ""
        local rc=$?
        ((rc == 130)) && return 130
        ((rc == 0)) || return 0
        [[ "$TUI_REPLY" == back ]] && return 0

        screen_request_detail "$TUI_REPLY"
        rc=$?
        ((rc == 130)) && return 130
    done
}
