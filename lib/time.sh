# shellcheck shell=bash
# lib/time.sh -- shared helpers for the screen-time engine (SPEC.md
# R-TIME-1..5, Appendix F). Trust boundary: every write under $TIME_ROOT
# is only ever called by the root ledger helper or `omarchy-kids-time
# grant` (I-3, R-TIME-1) -- the kid-run command only ever reads. Not
# meant to be executed directly; source it. Every path/env var: docs/time.md.

# Root-side callers may replace this explicit scratch-tree seam after sourcing.
TIME_SYSROOT=""
TIME_VARLIB="$TIME_SYSROOT/var/lib/omarchy-kids"

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
  h="${hm%%:*}"
  m="${hm##*:}"
  # Force base-10: bash treats a leading zero ("09") as octal otherwise,
  # and 08/09 are exactly the hours/minutes that trip that up.
  printf '%d\n' $((10#$h * 60 + 10#$m))
}

# time_logical_day NOW — "DAY\tWEEKEND" via lib/time.py (rolls at 04:00 local).
time_logical_day() {
  local now="$1" py out
  py="$(dirname "${BASH_SOURCE[0]}")/time.py"
  [[ -f "$py" ]] || py=/usr/lib/omarchy-kids/time.py
  out="$("$KIDS_PY" "$py" logical-day "$now")" || return 1
  printf '%s\t%s\n' "$(sed -n '1p' <<<"$out")" "$(sed -n '2p' <<<"$out")"
}

# time_conf KID KEY — omarchy-kids-conf get KID KEY, resolved as our own sibling.
time_conf() {
  local kid="$1" key="$2" bin
  bin="$(dirname "${BASH_SOURCE[0]}")/../bin/omarchy-kids-conf"
  [[ -x "$bin" ]] || bin=/usr/bin/omarchy-kids-conf
  "$bin" get "$kid" "$key"
}

# time_budget_minutes KID WEEKEND(yes/no) — budget_min(_weekend), via the band (R-TIME-2).
time_budget_minutes() {
  local kid="$1" weekend="$2" key=budget_min
  [[ "$weekend" == yes ]] && key=budget_min_weekend
  time_conf "$kid" "$key"
}

# time_lights_out KID WEEKEND(yes/no) — lights_out(_weekend) as HH:MM (R-TIME-2).
time_lights_out() {
  local kid="$1" weekend="$2" key=lights_out
  [[ "$weekend" == yes ]] && key=lights_out_weekend
  time_conf "$kid" "$key"
}

# time_kid_dir KID — /var/lib/omarchy-kids/<kid>, this kid's data area.
time_kid_dir() { printf '%s/%s\n' "$TIME_VARLIB" "$1"; }

# time_usage_dir KID — where per-day ledger/grant files live (R-TIME-1).
time_usage_dir() { printf '%s/usage\n' "$(time_kid_dir "$1")"; }

# time_usage_file KID DAY — one logical day's ledger: a bare integer,
# minutes used; missing means 0, never an error.
time_usage_file() { printf '%s/%s\n' "$(time_usage_dir "$1")" "$2"; }

# time_grant_file KID DAY — a one-off extension on DAY's budget (R-TIME-4).
time_grant_file() { printf '%s/%s.grant\n' "$(time_usage_dir "$1")" "$2"; }

# time_paused_file KID — its mere existence means "don't count" (R-TIME-2);
# nothing writes it yet, --pause isn't implemented (docs/exit.md).
time_paused_file() { printf '%s/paused\n' "$(time_kid_dir "$1")"; }

# time_is_paused KID — 0 (true) if the paused flag file exists.
time_is_paused() { [[ -e "$(time_paused_file "$1")" ]]; }

# time_read_int FILE — the integer FILE holds, or 0 if missing/corrupt.
time_read_int() {
  local file="$1" v
  [[ -r "$file" ]] || {
    printf '0\n'
    return 0
  }
  v="$(cat "$file" 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s\n' "$v"
}

# time_used_minutes KID DAY
time_used_minutes() { time_read_int "$(time_usage_file "$1" "$2")"; }

# time_granted_minutes KID DAY
time_granted_minutes() { time_read_int "$(time_grant_file "$1" "$2")"; }

# time_write_int FILE VALUE — root-only. Creates the parent dir if
# needed, writes VALUE mode 0644 (world-readable, like lib/conf.sh's).
time_write_int() {
  local file="$1" value="$2" dir tmp
  dir="$(dirname "$file")"
  [[ -d "$dir" ]] || install -d -m 0755 "$dir"
  tmp="$(mktemp "${file}.XXXXXX")"
  printf '%s\n' "$value" >"$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$file"
}

# time_ledger_add KID DAY MINUTES — adds MINUTES (usually 1) to DAY's used-minutes file. Root-only.
time_ledger_add() {
  local kid="$1" day="$2" add="$3" file cur
  file="$(time_usage_file "$kid" "$day")"
  cur="$(time_read_int "$file")"
  time_write_int "$file" "$((cur + add))"
}

# time_grant_add KID DAY MINUTES — adds MINUTES to DAY's one-off grant. Root-only.
time_grant_add() {
  local kid="$1" day="$2" add="$3" file cur
  file="$(time_grant_file "$kid" "$day")"
  cur="$(time_read_int "$file")"
  time_write_int "$file" "$((cur + add))"
}

# time_remaining_minutes KID DAY WEEKEND — budget + grant - used, floored at 0.
time_remaining_minutes() {
  local kid="$1" day="$2" weekend="$3" budget used granted remaining
  budget="$(time_budget_minutes "$kid" "$weekend")"
  used="$(time_used_minutes "$kid" "$day")"
  granted="$(time_granted_minutes "$kid" "$day")"
  remaining=$((budget + granted - used))
  ((remaining < 0)) && remaining=0
  printf '%s\n' "$remaining"
}

# time_toast_thresholds PREV CURR THRESHOLDS FIRED — R-TIME-3's toast
# decision (issue #40): prints thresholds firing now, then FIRED updated
# for next call. Fires when PREV > T >= CURR and T isn't already FIRED;
# a grant raising CURR back above a fired T un-fires it. docs/time.md.
time_toast_thresholds() {
  local prev="$1" curr="$2" thresholds="$3" fired="$4"
  local -a th_arr to_fire=()
  local t next_fired=""

  read -r -a th_arr <<<"$thresholds"

  # Un-fire anything CURR has now risen back above.
  for t in "${th_arr[@]+"${th_arr[@]}"}"; do
    if ((curr <= t)) && [[ " $fired " == *" $t "* ]]; then
      next_fired+="${next_fired:+ }$t"
    fi
  done
  fired="$next_fired"

  # Fire anything freshly crossed this step, highest threshold first.
  for t in "${th_arr[@]+"${th_arr[@]}"}"; do
    if [[ " $fired " != *" $t "* ]] && ((t >= curr)) &&
      { [[ -z "$prev" ]] || ((prev > t)); }; then
      to_fire+=("$t")
      fired+="${fired:+ }$t"
    fi
  done

  printf '%s\n' "${to_fire[*]+"${to_fire[*]}"}"
  printf '%s\n' "$fired"
}

# time_is_lights_out KID DAY WEEKEND NOW_HM — yes/no: reached lights-out.
time_is_lights_out() {
  local kid="$1" weekend="$2" now_hm="$3" lights_out now_min lo_min
  lights_out="$(time_lights_out "$kid" "$weekend")"
  now_min="$(time_minutes_since_midnight "$now_hm")"
  lo_min="$(time_minutes_since_midnight "$lights_out")"
  if ((now_min >= lo_min)); then printf 'yes\n'; else printf 'no\n'; fi
}

# time_next_boundary KID DAY WEEKEND NOW_HM — "KIND HH:MM": whichever of
# budget-runs-out or lights-out comes first.
time_next_boundary() {
  local kid="$1" day="$2" weekend="$3" now_hm="$4"
  local remaining lights_out now_min lo_min budget_out_min h m
  remaining="$(time_remaining_minutes "$kid" "$day" "$weekend")"
  lights_out="$(time_lights_out "$kid" "$weekend")"
  now_min="$(time_minutes_since_midnight "$now_hm")"
  lo_min="$(time_minutes_since_midnight "$lights_out")"
  budget_out_min=$((now_min + remaining))
  if ((remaining <= 0)) || ((budget_out_min >= lo_min)); then
    printf 'lights-out %s\n' "$lights_out"
  else
    h=$((budget_out_min / 60))
    m=$((budget_out_min % 60))
    printf 'budget %02d:%02d\n' "$h" "$m"
  fi
}
