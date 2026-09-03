# shellcheck shell=bash
# lib/wizard-advanced.sh — the wizard's Advanced path: a grouped checklist
# over every Appendix B cell not already collected by a shared screen
# (SPEC.md R-WIZ-2, R-WIZ-3, Appendix B; issue #20), reachable from A6
# and the summary's "Change something". Sourced by bin/omarchy-kids-
# wizard, which already defines every global/helper this file reads
# ($BAND, $DISPLAY_NAME, band_field, every tui_screen_* function); not
# meant to be sourced on its own. adv_get/adv_set read/write each row's
# value by variable name (bash 3.2 has no namerefs/associative arrays).
# Full row list and the six groups: docs/wizard.md.

ADV_KEYS=(web dns sites budget_min budget_min_weekend lights_out lights_out_weekend allowlist wifi level menu history_visible)

adv_varname() { # KEY -> the bash variable name holding its current value
    case "$1" in
        web) echo WEB_MODE ;;
        dns) echo DNS_MODE ;;
        sites) echo SITES ;;
        budget_min) echo BUDGET_MIN ;;
        budget_min_weekend) echo BUDGET_MIN_WEEKEND ;;
        lights_out) echo LIGHTS_OUT ;;
        lights_out_weekend) echo LIGHTS_OUT_WEEKEND ;;
        allowlist) echo ALLOWLIST_IDS ;;
        wifi) echo WIFI_MODE ;;
        level) echo LEVEL ;;
        menu) echo MENU_MODE ;;
        history_visible) echo HISTORY_VISIBLE ;;
    esac
}

adv_group_of() { # KEY -> the group its row is shown under
    case "$1" in
        web | dns | sites) echo "Web" ;;
        budget_min | budget_min_weekend | lights_out | lights_out_weekend) echo "Screen time" ;;
        allowlist) echo "Apps" ;;
        wifi) echo "Wi-Fi" ;;
        level | menu) echo "Desktop" ;;
        history_visible) echo "Data" ;;
    esac
}

adv_label_of() { # KEY -> the row's label, in parent words
    case "$1" in
        web) echo "Web access" ;;
        dns) echo "Safe-search DNS" ;;
        sites) echo "Allowed sites" ;;
        budget_min) echo "Minutes a day (weekdays)" ;;
        budget_min_weekend) echo "Minutes a day (weekends)" ;;
        lights_out) echo "Lights out (weekdays)" ;;
        lights_out_weekend) echo "Lights out (weekends)" ;;
        allowlist) echo "Starter apps" ;;
        wifi) echo "New Wi-Fi networks" ;;
        level) echo "Desktop level" ;;
        menu) echo "App menu" ;;
        history_visible) echo "Browsing history" ;;
    esac
}

# pack_sites BAND — comma-separated hosts from that band's pack [garden]
# table (share/packs/<band>.toml); empty for a band with no walled
# garden. The one pack field lib/conf.py already exposes for a kid's own
# `sites` (bin/omarchy-kids-conf's own pack_value), read here the same
# way for the same reason: it's a TOML array, not the single `key =
# "value"` line bin/omarchy-kids-wizard's own pack_field can sed for.
pack_sites() {
    "$PY" "$PYHELPER" pack-sites "$SHARE/packs/$1.toml" 2>/dev/null
}

# adv_default KEY — this band's (or its pack's) default value, in the
# same raw form `omarchy-kids-conf set` expects.
adv_default() {
    case "$1" in
        sites) pack_sites "$BAND" ;;
        allowlist) pack_field "$BAND" id | paste -sd, - ;;
        *) band_field "$BAND" "$1" ;;
    esac
}

# adv_get / adv_set KEY [VALUE] — the row's current value, read or
# written through its variable (adv_varname).
adv_get() {
    local var
    var="$(adv_varname "$1")"
    printf '%s' "${!var}"
}
adv_set() {
    local var
    var="$(adv_varname "$1")"
    printf -v "$var" '%s' "$2"
}

# adv_init — seeds every row to the current $BAND's default. Called once
# BAND is known (screen_band), before either path can reach a screen that
# changes one of these: Simple's own A7-A11 overwrite the five they
# cover; the rest keep this seed unless the Advanced checklist (or
# "Change something") changes them.
adv_init() {
    local k
    for k in "${ADV_KEYS[@]}"; do
        adv_set "$k" "$(adv_default "$k")"
    done
}

friendly_menu() {
    case "$1" in
        trimmed) echo "Fewer icons, easier to scan" ;;
        full) echo "Every app Omarchy normally shows" ;;
        *) echo "$1" ;;
    esac
}
friendly_yesno() {
    case "$1" in
        yes) echo "Yes" ;;
        no) echo "No" ;;
        *) echo "$1" ;;
    esac
}
friendly_dns() {
    case "$1" in
        cloudflare-family) echo "Cloudflare Family" ;;
        cleanbrowsing-family) echo "CleanBrowsing Family" ;;
        custom:*) echo "Custom (${1#custom:})" ;;
        *) echo "$1" ;;
    esac
}
friendly_sites() {
    [[ -z "$1" ]] && echo "(none)" || echo "$1"
}
friendly_allowlist() {
    local csv="$1" id oldifs="$IFS" out=""
    if [[ -z "$csv" ]]; then
        echo "(none selected)"
        return
    fi
    IFS=,
    for id in $csv; do
        IFS="$oldifs"
        [[ -z "$id" ]] && continue
        [[ -n "$out" ]] && out+=", "
        out+="$(app_label_for "$BAND" "$id")"
    done
    IFS="$oldifs"
    [[ -z "$out" ]] && out="(none selected)"
    echo "$out"
}

# adv_friendly KEY VALUE — human words for one of KEY's raw values,
# reusing the same friendly_* functions the Easy summary already uses
# for web/wifi so both paths describe a value the same way.
adv_friendly() {
    local key="$1" value="$2"
    case "$key" in
        web) friendly_web_mode "$value" ;;
        wifi) friendly_wifi_mode "$value" ;;
        dns) friendly_dns "$value" ;;
        menu) friendly_menu "$value" ;;
        history_visible) friendly_yesno "$value" ;;
        level) echo "Level $value" ;;
        budget_min | budget_min_weekend) echo "$value minutes a day" ;;
        lights_out | lights_out_weekend) echo "$value" ;;
        allowlist) friendly_allowlist "$value" ;;
        sites) friendly_sites "$value" ;;
        *) echo "$value" ;;
    esac
}

# mark_if_changed KEY TEXT — TEXT, plus " (custom)" when KEY's current
# value no longer matches this band's default: the summary's "distinct
# ... mark" for an override (issue #20, point 3), the same idea R-BAND-2
# already applies to what actually gets *written*.
mark_if_changed() {
    local key="$1" text="$2"
    if [[ "$(adv_get "$key")" == "$(adv_default "$key")" ]]; then
        printf '%s' "$text"
    else
        printf '%s (custom)' "$text"
    fi
}

# adv_append_row ARRAYNAME "label|value" — appends one row to a caller's
# array by name (bash-3.2-safe: no namerefs, same idiom lib/tui.sh's
# _tui_array_copy uses to read one, just for writing one element).
adv_append_row() {
    local __adv_arr="$1" __adv_row="$2"
    # shellcheck disable=SC1087 # $__adv_arr[@] is the array-name being
    # built for eval, not an expansion shellcheck can see through
    eval "$__adv_arr+=(\"\$__adv_row\")"
}

# adv_summary_extra_rows ARRAYNAME — appends one "label|value (custom)"
# row for each of the seven keys Simple never shows on its own summary
# (dns, sites, menu, history_visible, and the two weekend fields),
# but only the ones Advanced (or "Change something") actually changed —
# so a kid set up entirely through Simple gets exactly the same summary
# it always has.
adv_summary_extra_rows() {
    local arrname="$1"
    if [[ "$(adv_get dns)" != "$(adv_default dns)" ]]; then
        adv_append_row "$arrname" "Safe-search DNS|$(friendly_dns "$DNS_MODE") (custom)"
    fi
    if [[ "$(adv_get menu)" != "$(adv_default menu)" ]]; then
        adv_append_row "$arrname" "App menu|$(friendly_menu "$MENU_MODE") (custom)"
    fi
    if [[ "$(adv_get history_visible)" != "$(adv_default history_visible)" ]]; then
        adv_append_row "$arrname" "Browsing history|$(friendly_yesno "$HISTORY_VISIBLE") (custom)"
    fi
    if [[ "$(adv_get budget_min_weekend)" != "$(adv_default budget_min_weekend)" ]]; then
        adv_append_row "$arrname" "Screen time (weekends)|$BUDGET_MIN_WEEKEND minutes a day (custom)"
    fi
    if [[ "$(adv_get lights_out_weekend)" != "$(adv_default lights_out_weekend)" ]]; then
        adv_append_row "$arrname" "Bedtime (weekends)|$LIGHTS_OUT_WEEKEND (custom)"
    fi
    if [[ "$(adv_get sites)" != "$(adv_default sites)" ]]; then
        adv_append_row "$arrname" "Allowed sites|$SITES (custom)"
    fi
}

# adv_row_line KEY — one "value|label|reason" element for the checklist's
# tui_screen_choose (docs/tui.md): group-prefixed label, and a reason
# line naming both the band default and, when it differs, the current
# choice — the row-level twin of mark_if_changed above.
adv_row_line() {
    local key="$1" group label default_disp current_disp reason
    group="$(adv_group_of "$key")"
    label="$(adv_label_of "$key")"
    default_disp="$(adv_friendly "$key" "$(adv_default "$key")")"
    if [[ "$(adv_get "$key")" == "$(adv_default "$key")" ]]; then
        reason="Band default: $default_disp"
    else
        current_disp="$(adv_friendly "$key" "$(adv_get "$key")")"
        reason="Band default: $default_disp — now: $current_disp (changed)"
    fi
    printf '%s|[%s] %s|%s' "$key" "$group" "$label" "$reason"
}

# validate_dns_url CANDIDATE — A2/A8-style validator (lib/tui.sh's
# contract): print nothing and return 0 for a usable address, else print
# a one-line reason and return non-zero to redraw and ask again.
validate_dns_url() {
    local val="$1"
    if [[ -z "$val" || "$val" == *[[:space:]]* ]]; then
        echo "Type a DNS address with no spaces, like doh.example.com."
        return 1
    fi
    return 0
}

# validate_sites_list CANDIDATE — the same comma-separated-hostnames
# shape bin/omarchy-kids-conf's own validate_value requires for `sites`,
# checked here too so a bad value never reaches Apply's `omarchy-kids-conf
# set` in the first place.
validate_sites_list() {
    local val="$1"
    if [[ "$val" =~ ^[a-z0-9.-]+(,[a-z0-9.-]+)*$ || -z "$val" ]]; then
        return 0
    fi
    echo "Comma-separated hostnames only, like pbskids.org,starfall.com."
    return 1
}

# adv_edit_enum KEY TITLE STEP TOTAL CHOICE... — a plain tui_screen_choose
# over KEY's own enum values, preselecting its *current* value (not the
# band default, so re-opening a changed row shows the change).
adv_edit_enum() {
    local key="$1" title="$2" step="$3" total="$4"
    shift 4
    local -a choices=("$@")
    tui_screen_choose "$title" "$step" "$total" 0 "" choices "$(adv_get "$key")"
    local rc=$?
    ((rc == 0)) || return $rc
    adv_set "$key" "$TUI_REPLY"
    return 0
}

# adv_edit_number / adv_edit_time KEY TITLE STEP TOTAL — tui_screen_input
# with the same validators A8's "I'll set my own" custom fields use.
adv_edit_number() {
    local key="$1" title="$2" step="$3" total="$4"
    tui_screen_input "$title" "$step" "$total" 0 "" \
        text "A number of minutes, 1 to 1440." validate_budget_minutes
    local rc=$?
    ((rc == 0)) || return $rc
    adv_set "$key" "$TUI_REPLY"
    return 0
}
adv_edit_time() {
    local key="$1" title="$2" step="$3" total="$4"
    tui_screen_input "$title" "$step" "$total" 0 "" \
        text "24-hour time, like 19:30." validate_lights_out
    local rc=$?
    ((rc == 0)) || return $rc
    adv_set "$key" "$TUI_REPLY"
    return 0
}

adv_edit_sites() {
    local step="$1" total="$2"
    tui_screen_input "Which sites can $DISPLAY_NAME visit?" "$step" "$total" 0 "" \
        text "Comma-separated hostnames, like pbskids.org,starfall.com." validate_sites_list
    local rc=$?
    ((rc == 0)) || return $rc
    adv_set sites "$TUI_REPLY"
    return 0
}

# adv_edit_dns STEP TOTAL — two fixed providers plus "Type my own", which
# opens one more field for the address (Appendix B's `custom:<url>`).
# Esc on that second field returns to the checklist with dns untouched,
# same as any other editor (the provider pick alone is discarded too,
# nothing here is committed until this function itself returns 0).
adv_edit_dns() {
    local step="$1" total="$2"
    local -a choices=(
        "cloudflare-family|Cloudflare Family|Blocks adult content at the DNS level."
        "cleanbrowsing-family|CleanBrowsing Family|A second safe-search DNS provider."
        "custom|Type my own|Enter any DNS provider's address."
    )
    local preselect current
    current="$(adv_get dns)"
    case "$current" in
        custom:*) preselect="custom" ;;
        *) preselect="$current" ;;
    esac
    tui_screen_choose "Which safe-search DNS should $DISPLAY_NAME use?" "$step" "$total" 0 "" choices "$preselect"
    local rc=$?
    ((rc == 0)) || return $rc
    if [[ "$TUI_REPLY" == custom ]]; then
        tui_screen_input "What DNS address?" "$step" "$total" 0 "" \
            text "Like doh.example.com." validate_dns_url
        rc=$?
        ((rc == 0)) || return $rc
        adv_set dns "custom:$TUI_REPLY"
    else
        adv_set dns "$TUI_REPLY"
    fi
    return 0
}

# adv_edit_allowlist STEP TOTAL — the same per-app walk A9's "Let me
# pick" uses (bin/omarchy-kids-wizard's apps_pick_walk), shared rather
# than duplicated (issue #20's own brief: "the per-app checklist from the
# Easy path for apps"). Always finishes (there's no single "Esc the whole
# editor" gesture mid-walk — apps_pick_walk's own contract is that an Esc
# on one app is just "No" for that app, same as A9), so this never
# returns 1.
adv_edit_allowlist() {
    local step="$1" total="$2"
    apps_pick_walk "$step" "$total"
    local rc=$?
    ((rc == 130)) && return 130
    adv_set allowlist "$TUI_REPLY"
    return 0
}

# adv_edit KEY STEP TOTAL — dispatches to the right editor for one row.
adv_edit() {
    local key="$1" step="$2" total="$3"
    case "$key" in
        web)
            adv_edit_enum web "What can $DISPLAY_NAME see on the web?" "$step" "$total" \
                "garden|Only sites you choose|A short list you can grow. Best for younger kids." \
                "filtered|Filtered open web|Adult content blocked, safe search on." \
                "none|No browser|Simplest and safest; no browser at all."
            ;;
        wifi)
            adv_edit_enum wifi "Can $DISPLAY_NAME join new Wi-Fi?" "$step" "$total" \
                "parent|Ask me first|Wi-Fi requests go through you." \
                "helper|On their own, safely|They can join school or café Wi-Fi. The network can't change what's blocked."
            ;;
        level)
            adv_edit_enum level "How should $DISPLAY_NAME's desktop work?" "$step" "$total" \
                "1|One thing at a time|Simplest — one app fills the screen." \
                "2|Two things side by side|Split-screen multitasking." \
                "3|The full desktop|Everything Omarchy normally offers."
            ;;
        menu)
            adv_edit_enum menu "How many icons should $DISPLAY_NAME's app menu show?" "$step" "$total" \
                "trimmed|Trimmed|Fewer icons, easier to scan." \
                "full|Full|Every app Omarchy normally shows."
            ;;
        history_visible)
            adv_edit_enum history_visible "Can $DISPLAY_NAME see their own browsing history?" "$step" "$total" \
                "yes|Yes|The same history the parent bar can already show." \
                "no|No|History stays hidden from $DISPLAY_NAME."
            ;;
        dns) adv_edit_dns "$step" "$total" ;;
        budget_min) adv_edit_number budget_min "How many minutes a day, on weekdays?" "$step" "$total" ;;
        budget_min_weekend) adv_edit_number budget_min_weekend "How many minutes a day, on weekends?" "$step" "$total" ;;
        lights_out) adv_edit_time lights_out "Lights out at, on weekdays?" "$step" "$total" ;;
        lights_out_weekend) adv_edit_time lights_out_weekend "Lights out at, on weekends?" "$step" "$total" ;;
        sites) adv_edit_sites "$step" "$total" ;;
        allowlist) adv_edit_allowlist "$step" "$total" ;;
        *) return 1 ;;
    esac
}

# screen_advanced_checklist STEP TOTAL — the grouped checklist itself
# (Appendix A A13a): one row per adv_row_line, in group order, plus
# "Done customizing". Returns 0 once the parent picks that (proceed —
# bin/omarchy-kids-wizard decides what "proceed" means from each of its
# two call sites), 1 on Esc at the row list itself (go back a screen —
# also decided by the caller), 130 on Ctrl+C (leave, nothing written).
# Nothing in this whole file ever calls omarchy-kids-conf or run_priv —
# every row is just a bash variable until Apply's maybe_override calls
# read it (point 3 of issue #20: "writes only overrides to the profile").
screen_advanced_checklist() {
    local step="$1" total="$2"
    while true; do
        local -a choices=()
        local k
        for k in "${ADV_KEYS[@]}"; do
            choices+=("$(adv_row_line "$k")")
        done
        choices+=("done|Done customizing|")

        tui_screen_choose "Every setting for $DISPLAY_NAME" "$step" "$total" 0 "" choices "done" \
            "Enter opens a setting · Esc back · Ctrl+C leave (nothing changes)"
        local rc=$?
        ((rc == 0)) || return $rc

        [[ "$TUI_REPLY" == "done" ]] && return 0

        adv_edit "$TUI_REPLY" "$step" "$total"
        rc=$?
        ((rc == 130)) && return 130
        # rc 0 (the editor set a new value) or 1 (Esc'd the editor, so
        # the row is whatever it already was): either way, redraw this
        # same checklist rather than leaving it.
    done
}
