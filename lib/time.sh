# shellcheck shell=bash
# lib/time.sh — shared helpers for the screen-time engine (SPEC.md
# R-TIME-1..5, Appendix F): bin/omarchy-kids-time-ledger (root, writes)
# and bin/omarchy-kids-time (the kid, reads). Trust boundary: every
# function here that writes under $TIME_ROOT is only ever called by the
# root ledger helper (or `omarchy-kids-time grant`, which itself refuses
# to run as anyone but root) -- the kid-run command only ever reads, so
# it can show a stale number if buggy but has no path to make the ledger
# lie (I-3, R-TIME-1). Every "now" is OMARCHY_KIDS_NOW when set, else the
# real local clock -- no timezone handling anywhere, same as bands.toml.
# Not meant to be executed directly; source it. Every path/env var:
# docs/time.md.

TIME_SYSROOT="${OMARCHY_KIDS_ROOT:-}"
TIME_VARLIB="$TIME_SYSROOT/var/lib/omarchy-kids"
TIME_CONF_BIN="${OMARCHY_KIDS_CONF_BIN:-}"
TIME_PY="${OMARCHY_KIDS_CONF_PY:-python3}"
TIME_PYHELPER="${OMARCHY_KIDS_TIME_PY:-}"

# time_now — prints "YYYY-MM-DD HH:MM:SS", local wall clock.
time_now() {
    printf '%s\n' "${OMARCHY_KIDS_NOW:-$(date '+%Y-%m-%d %H:%M:%S')}"
}

# time_hm NOW — prints NOW's "HH:MM" (the last field, minus seconds).
time_hm() {
    local now="$1"
    printf '%s\n' "${now#* }" | cut -c1-5
}

# time_minutes_since_midnight HH:MM — an integer 0..1439.
time_minutes_since_midnight() {
    local hm="$1" h m
    h="${hm%%:*}"; m="${hm##*:}"
    # Force base-10: bash treats a leading zero ("09") as octal otherwise,
    # and 08/09 are exactly the hours/minutes that trip that up.
    printf '%d\n' $((10#$h * 60 + 10#$m))
}

# time_logical_day NOW — prints "DAY\tWEEKEND" (DAY: YYYY-MM-DD; WEEKEND:
# yes/no), via lib/time.py (day rolls at 04:00 local, R-TIME-2/Appendix F).
time_logical_day() {
    local now="$1" py="$TIME_PYHELPER" out
    [[ -n "$py" ]] || py="$(dirname "${BASH_SOURCE[0]}")/time.py"
    [[ -f "$py" ]] || py=/usr/lib/omarchy-kids/time.py
    out="$("$TIME_PY" "$py" logical-day "$now")" || return 1
    printf '%s\t%s\n' "$(sed -n '1p' <<<"$out")" "$(sed -n '2p' <<<"$out")"
}

# time_conf KID KEY — omarchy-kids-conf get KID KEY, resolving the
# binary the same way every other command beside it does.
time_conf() {
    local kid="$1" key="$2" bin="$TIME_CONF_BIN"
    if [[ -z "$bin" ]]; then
        bin="$(dirname "${BASH_SOURCE[0]}")/../bin/omarchy-kids-conf"
        [[ -x "$bin" ]] || bin=/usr/bin/omarchy-kids-conf
    fi
    "$bin" get "$kid" "$key"
}

# time_budget_minutes KID WEEKEND(yes/no) — budget_min or
# budget_min_weekend, resolved through the band (R-TIME-2).
time_budget_minutes() {
    local kid="$1" weekend="$2" key=budget_min
    [[ "$weekend" == yes ]] && key=budget_min_weekend
    time_conf "$kid" "$key"
}

# time_lights_out KID WEEKEND(yes/no) — lights_out or
# lights_out_weekend, as HH:MM (R-TIME-2).
time_lights_out() {
    local kid="$1" weekend="$2" key=lights_out
    [[ "$weekend" == yes ]] && key=lights_out_weekend
    time_conf "$kid" "$key"
}

# time_kid_dir KID — /var/lib/omarchy-kids/<kid>, this kid's whole
# recorded-data area (R-DATA-1 will add siblings to usage/ later; this
# issue only ever touches usage/ and paused).
time_kid_dir() { printf '%s/%s\n' "$TIME_VARLIB" "$1"; }

# time_usage_dir KID — where per-day ledger/grant files live (R-TIME-1:
# "per-day totals under /var/lib/omarchy-kids/<name>/usage/").
time_usage_dir() { printf '%s/usage\n' "$(time_kid_dir "$1")"; }

# time_usage_file KID DAY — the ledger file for one logical day: a bare
# integer, minutes used. Root-owned, root-written (see this file's
# header); missing means 0, never an error.
time_usage_file() { printf '%s/%s\n' "$(time_usage_dir "$1")" "$2"; }

# time_grant_file KID DAY — a one-off extension on top of DAY's budget
# (R-TIME-4: "'More time' extends today's budget only"), same shape as
# the usage file. Missing means 0.
time_grant_file() { printf '%s/%s.grant\n' "$(time_usage_dir "$1")" "$2"; }

# time_paused_file KID — its mere existence means "don't count"
# (R-TIME-2: "Paused or locked time does not count"), independent of
# whatever loginctl says about the session. Nothing in this issue
# creates this file yet (R-EXIT --pause isn't implemented -- see
# bin/omarchy-kids-exit's own header); it exists so the ledger is ready
# the day something does.
time_paused_file() { printf '%s/paused\n' "$(time_kid_dir "$1")"; }

# time_is_paused KID — 0 (true) if the paused flag file exists.
time_is_paused() { [[ -e "$(time_paused_file "$1")" ]]; }

# time_read_int FILE — the integer a ledger/grant file holds, or 0 if
# the file is missing, empty, or not a plain non-negative integer (a
# corrupt file counts as "nothing recorded yet", not a crash).
time_read_int() {
    local file="$1" v
    [[ -r "$file" ]] || { printf '0\n'; return 0; }
    v="$(cat "$file" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    printf '%s\n' "$v"
}

# time_used_minutes KID DAY
time_used_minutes() { time_read_int "$(time_usage_file "$1" "$2")"; }

# time_granted_minutes KID DAY
time_granted_minutes() { time_read_int "$(time_grant_file "$1" "$2")"; }

# time_write_int FILE VALUE — root-only callers (see header): creates
# the parent directory (0755) if needed, writes VALUE, mode 0644 (world
# -readable, like every other root-owned-but-kid-readable file this
# package writes -- e.g. lib/conf.sh's kid profiles).
time_write_int() {
    local file="$1" value="$2" dir tmp
    dir="$(dirname "$file")"
    [[ -d "$dir" ]] || install -d -m 0755 "$dir"
    tmp="$(mktemp "${file}.XXXXXX")"
    printf '%s\n' "$value" >"$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
}

# time_ledger_add KID DAY MINUTES — adds MINUTES (usually 1, from one
# timer tick) to DAY's used-minutes file. Root-only (see header).
time_ledger_add() {
    local kid="$1" day="$2" add="$3" file cur
    file="$(time_usage_file "$kid" "$day")"
    cur="$(time_read_int "$file")"
    time_write_int "$file" "$((cur + add))"
}

# time_grant_add KID DAY MINUTES — adds MINUTES to DAY's one-off grant.
# Root-only (see header).
time_grant_add() {
    local kid="$1" day="$2" add="$3" file cur
    file="$(time_grant_file "$kid" "$day")"
    cur="$(time_read_int "$file")"
    time_write_int "$file" "$((cur + add))"
}

# time_remaining_minutes KID DAY WEEKEND — budget + grant - used,
# floored at 0 (never negative: a kid who somehow used more than their
# budget is just at 0 remaining, not "owes" future days).
time_remaining_minutes() {
    local kid="$1" day="$2" weekend="$3" budget used granted remaining
    budget="$(time_budget_minutes "$kid" "$weekend")"
    used="$(time_used_minutes "$kid" "$day")"
    granted="$(time_granted_minutes "$kid" "$day")"
    remaining=$((budget + granted - used))
    (( remaining < 0 )) && remaining=0
    printf '%s\n' "$remaining"
}

# time_toast_thresholds PREV CURR THRESHOLDS FIRED — the pure decision
# behind R-TIME-3's toast warnings (issue #40), table-tested in
# test/shell.d/time-test.sh. Prints two lines: thresholds firing on THIS
# check, then FIRED updated for the next call. A threshold T fires when
# PREV > T >= CURR and isn't already in FIRED (PREV="" reads as
# +infinity); a grant raising CURR back above a fired T drops it from
# FIRED so it can fire again next crossing. Full contract and the
# stale-toast bug this fixed: docs/time.md.
time_toast_thresholds() {
    local prev="$1" curr="$2" thresholds="$3" fired="$4"
    local -a th_arr to_fire=()
    local t next_fired=""

    read -r -a th_arr <<<"$thresholds"

    # Un-fire anything CURR has now risen back above.
    for t in "${th_arr[@]+"${th_arr[@]}"}"; do
        if (( curr <= t )) && [[ " $fired " == *" $t "* ]]; then
            next_fired+="${next_fired:+ }$t"
        fi
    done
    fired="$next_fired"

    # Fire anything freshly crossed this step, highest threshold first.
    for t in "${th_arr[@]+"${th_arr[@]}"}"; do
        if [[ " $fired " != *" $t "* ]] && (( t >= curr )) \
            && { [[ -z "$prev" ]] || (( prev > t )); }; then
            to_fire+=("$t")
            fired+="${fired:+ }$t"
        fi
    done

    printf '%s\n' "${to_fire[*]+"${to_fire[*]}"}"
    printf '%s\n' "$fired"
}

# time_is_lights_out KID DAY WEEKEND NOW_HM — yes/no: has the clock
# reached this kid's lights-out for today.
time_is_lights_out() {
    local kid="$1" weekend="$2" now_hm="$3" lights_out now_min lo_min
    lights_out="$(time_lights_out "$kid" "$weekend")"
    now_min="$(time_minutes_since_midnight "$now_hm")"
    lo_min="$(time_minutes_since_midnight "$lights_out")"
    if (( now_min >= lo_min )); then printf 'yes\n'; else printf 'no\n'; fi
}

# time_next_boundary KID DAY WEEKEND NOW_HM — one line, "KIND HH:MM":
# KIND is "budget" (the clock time the budget runs out, if that's
# sooner) or "lights-out" (this kid's lights-out time, if that's
# sooner or the budget is already exhausted).
time_next_boundary() {
    local kid="$1" day="$2" weekend="$3" now_hm="$4"
    local remaining lights_out now_min lo_min budget_out_min h m
    remaining="$(time_remaining_minutes "$kid" "$day" "$weekend")"
    lights_out="$(time_lights_out "$kid" "$weekend")"
    now_min="$(time_minutes_since_midnight "$now_hm")"
    lo_min="$(time_minutes_since_midnight "$lights_out")"
    budget_out_min=$((now_min + remaining))
    if (( remaining <= 0 )) || (( budget_out_min >= lo_min )); then
        printf 'lights-out %s\n' "$lights_out"
    else
        h=$((budget_out_min / 60)); m=$((budget_out_min % 60))
        printf 'budget %02d:%02d\n' "$h" "$m"
    fi
}
