# shellcheck shell=bash
# lib/data.sh — shared helpers for recorded data (SPEC.md R-DATA-1..5,
# issue #27): bin/omarchy-kids-data (reads and prunes) and the
# launch-log folding step bin/omarchy-kids-time-ledger runs once a
# minute alongside its own screen-time tick.
#
# Three things live under /var/lib/omarchy-kids/<kid>/ (spec 5.1) that
# this file touches:
#   usage/<day>        screen-time minutes — lib/time.sh's own tree
#                       (R-TIME-1); this file only *reads* it (for
#                       summaries) and prunes old days for retention.
#   launches.log        one "<timestamp> <app id>" line per Level 1
#                        tile launch (R-DATA-1's "app launches"). Root-
#                        owned, append-only in normal operation.
#   launches.offset      a plain integer byte count: how much of the
#                        kid's own *runtime* launches log (below) has
#                        already been folded into launches.log. Root
#                        housekeeping, not itself recorded data.
#
# The trust boundary is the same shape lib/time.sh's own header
# describes for screen-time minutes, one level up: a kid's own Level 1
# launcher can only ever write to *its own* runtime dir
# ($XDG_RUNTIME_DIR/omarchy-kids/launches.log, via
# `omarchy-kids-launcher-ctl log`) — never to the root-owned copy under
# /var/lib. data_fold_launches below is the one thing that promotes a
# kid's own unverified claim ("I opened gcompris at 10:02") into the
# log a parent's panel and the kid's own "what my grown-ups can see"
# screen both read; it is only ever called by bin/omarchy-kids-time-
# ledger's tick (root, once a minute), never by anything that runs as
# the kid.
#
# Folding is deliberately simple, not byte-exact-safe against a torn
# write: each fold takes every byte written to the runtime file since
# the last fold, full stop. A launch line is one short `printf` append
# (bin/omarchy-kids-launcher-ctl's cmd_log), well under PIPE_BUF, so a
# line torn mid-write at the exact instant a tick runs is not a
# realistic risk here — this repo already accepts comparable slop
# elsewhere (lib/time.sh's own R-TIME-1 resolution note).
#
# Not meant to be executed directly; source it from a command:
#   source "$DIR/lib/data.sh"
#
# Every path is overridable for tests, same convention as lib/time.sh:
#   OMARCHY_KIDS_ROOT           scratch prefix for /var/lib/omarchy-kids and /run
#   OMARCHY_KIDS_RUN_USER_BASE  default /run/user (a kid's own XDG_RUNTIME_DIR
#                                is assumed to be <base>/<uid>, systemd-logind's
#                                own convention)
#   OMARCHY_KIDS_HOMES_BASE     default /home (a kid's home is <base>/<kid>)
#   OMARCHY_KIDS_CONF_PY / OMARCHY_KIDS_DATA_PY  python3 and lib/data.py

DATA_SYSROOT="${OMARCHY_KIDS_ROOT:-}"
DATA_VARLIB="$DATA_SYSROOT/var/lib/omarchy-kids"
DATA_RUN_USER_BASE="${OMARCHY_KIDS_RUN_USER_BASE:-/run/user}"
DATA_HOMES_BASE="${OMARCHY_KIDS_HOMES_BASE:-/home}"
DATA_PY_BIN="${OMARCHY_KIDS_CONF_PY:-python3}"
DATA_PYHELPER="${OMARCHY_KIDS_DATA_PY:-}"

# data_py ARGS... — runs lib/data.py, resolving it the same way
# lib/time.sh resolves lib/time.py.
data_py() {
    local py="$DATA_PYHELPER"
    [[ -n "$py" ]] || py="$(dirname "${BASH_SOURCE[0]}")/data.py"
    [[ -f "$py" ]] || py=/usr/lib/omarchy-kids/data.py
    "$DATA_PY_BIN" "$py" "$@"
}

data_kid_dir() { printf '%s/%s\n' "$DATA_VARLIB" "$1"; }
data_usage_dir() { printf '%s/usage\n' "$(data_kid_dir "$1")"; }
data_launches_file() { printf '%s/launches.log\n' "$(data_kid_dir "$1")"; }
data_launches_offset_file() { printf '%s/launches.offset\n' "$(data_kid_dir "$1")"; }
data_home_dir() { printf '%s/%s\n' "$DATA_HOMES_BASE" "$1"; }
data_chromium_history() { printf '%s/.config/chromium/Default/History\n' "$(data_home_dir "$1")"; }

# data_kid_uid KID — `id -u KID`, empty (and non-zero) if there's no
# such account. A stub `id` on PATH (same shape as time-test.sh's
# loginctl stub) drives this in tests.
data_kid_uid() { id -u "$1" 2>/dev/null; }

# data_runtime_launches_file KID — the kid-writable source
# `omarchy-kids-launcher-ctl log` appends to, as seen by root:
# $OMARCHY_KIDS_ROOT/run/user/<uid>/omarchy-kids/launches.log
# (systemd-logind's own $XDG_RUNTIME_DIR convention, not something this
# package invents). Returns 1 with nothing printed if KID has no uid.
data_runtime_launches_file() {
    local kid="$1" uid
    uid="$(data_kid_uid "$kid")" || return 1
    [[ -n "$uid" ]] || return 1
    printf '%s%s/%s/omarchy-kids/launches.log\n' "$DATA_SYSROOT" "$DATA_RUN_USER_BASE" "$uid"
}

# data_read_int FILE — same contract as lib/time.sh's time_read_int
# (missing/empty/non-integer all read as 0, never an error).
data_read_int() {
    local file="$1" v
    [[ -r "$file" ]] || { printf '0\n'; return 0; }
    v="$(cat "$file" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    printf '%s\n' "$v"
}

# data_write_int FILE VALUE — same shape as lib/time.sh's time_write_int:
# creates the parent dir (0755) if needed, writes atomically, mode 0644.
data_write_int() {
    local file="$1" value="$2" dir tmp
    dir="$(dirname "$file")"
    [[ -d "$dir" ]] || install -d -m 0755 "$dir"
    tmp="$(mktemp "${file}.XXXXXX")"
    printf '%s\n' "$value" >"$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
}

# data_fold_launches KID — root-only (see header): appends whatever is
# new in KID's own runtime launches log onto their root-owned
# launches.log, then remembers how far it got. A missing runtime file
# (no session yet, or a session that never opened a Level 1 tile) is
# not an error, just nothing to fold. If the runtime file is smaller
# than the last recorded offset, it must be a fresh one — a new login
# gets a fresh $XDG_RUNTIME_DIR tmpfs — so fold from the start again
# instead of treating that as corruption.
data_fold_launches() {
    local kid="$1" src dest offfile off size dir
    src="$(data_runtime_launches_file "$kid")" || return 0
    [[ -r "$src" ]] || return 0
    dest="$(data_launches_file "$kid")"
    offfile="$(data_launches_offset_file "$kid")"
    off="$(data_read_int "$offfile")"
    size="$(wc -c <"$src" 2>/dev/null | tr -d '[:space:]')"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    (( off > size )) && off=0
    (( size <= off )) && return 0
    dir="$(dirname "$dest")"
    [[ -d "$dir" ]] || install -d -m 0755 "$dir"
    [[ -e "$dest" ]] || { : >"$dest"; chmod 0644 "$dest"; }
    tail -c "+$((off + 1))" "$src" >>"$dest"
    data_write_int "$offfile" "$size"
}

# data_history_visible KID CONF_BIN — "yes"/"no" (Appendix B's
# history_visible key, default "yes"). Centralized here so
# bin/omarchy-kids-data and bin/omarchy-kids-panel read the R-DATA-4
# gate the exact same way.
data_history_visible() {
    local kid="$1" conf_bin="$2" v
    v="$("$conf_bin" get "$kid" history_visible 2>/dev/null)" || v=yes
    [[ "$v" == "no" ]] && { printf 'no\n'; return 0; }
    printf 'yes\n'
}
