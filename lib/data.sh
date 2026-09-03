# shellcheck shell=bash
# lib/data.sh — shared helpers for recorded data (SPEC.md R-DATA-1..5,
# issue #27): bin/omarchy-kids-data (reads and prunes) and the
# launch-log folding step bin/omarchy-kids-time-ledger runs once a
# minute alongside its own screen-time tick. Trust boundary, same shape
# as lib/time.sh's: a kid's Level 1 launcher can only ever write its own
# runtime launches log, never the root-owned
# /var/lib/omarchy-kids/<kid>/launches.log directly -- data_fold_launches
# (root only, called from time-ledger's tick) is the one thing that
# promotes a kid's unverified claim into that file. launches.offset is
# "<inode> <byte-offset>", not a plain byte count, so a fresh login's new
# $XDG_RUNTIME_DIR tmpfs (a new inode at the same path) is never read as
# a continuation of the previous session's file. Not meant to be executed
# directly; source it. Every path/env var, and the three files this
# touches under /var/lib/omarchy-kids/<kid>/: docs/data.md.

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

# data_stat_inode FILE — FILE's inode number, BSD stat first then GNU
# (same fallback order as bin/omarchy-kids-check's stat_group). Empty
# if FILE doesn't exist.
data_stat_inode() {
    stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1" 2>/dev/null
}

# data_read_offset FILE — "<inode> <byte-offset>" last recorded for the
# runtime log FILE tracks, one line so a fold can never end up with one
# updated and not the other. Both read as 0 if FILE is missing, empty,
# or (an upgrade from before this pairing existed) just a bare byte
# count -- 0 never matches a real inode, so that reads as "unknown
# file", the same as a fresh login would.
data_read_offset() {
    local file="$1" inode off
    read -r inode off <"$file" 2>/dev/null
    [[ "$inode" =~ ^[0-9]+$ ]] || inode=0
    [[ "$off" =~ ^[0-9]+$ ]] || off=0
    printf '%s %s\n' "$inode" "$off"
}

# data_write_offset FILE INODE OFFSET — same atomic-write shape as
# data_write_int.
data_write_offset() {
    local file="$1" inode="$2" off="$3" dir tmp
    dir="$(dirname "$file")"
    [[ -d "$dir" ]] || install -d -m 0755 "$dir"
    tmp="$(mktemp "${file}.XXXXXX")"
    printf '%s %s\n' "$inode" "$off" >"$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
}

# data_fold_launches KID — root-only (see header): appends whatever is
# new in KID's own runtime launches log onto their root-owned
# launches.log, then remembers how far it got, keyed to that file's
# inode as well as its byte offset. A missing runtime file (no session
# yet, or a session that never opened a Level 1 tile) is not an error,
# just nothing to fold. A new login gets a fresh $XDG_RUNTIME_DIR tmpfs
# at the same path -- a different inode, one telltale a size check
# alone can miss if the new file happens to grow past the old offset
# before the next tick runs -- so either that or a file now shorter
# than what was already folded means "this is a new file", and folding
# starts over from byte 0 instead of skipping or erroring.
data_fold_launches() {
    local kid="$1" src dest offfile off size dir inode saved_inode
    src="$(data_runtime_launches_file "$kid")" || return 0
    [[ -r "$src" ]] || return 0
    dest="$(data_launches_file "$kid")"
    offfile="$(data_launches_offset_file "$kid")"
    inode="$(data_stat_inode "$src")"; [[ "$inode" =~ ^[0-9]+$ ]] || inode=0
    read -r saved_inode off <<<"$(data_read_offset "$offfile")"
    size="$(wc -c <"$src" 2>/dev/null | tr -d '[:space:]')"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    { [[ "$inode" != "$saved_inode" ]] || (( off > size )); } && off=0
    if (( size > off )); then
        dir="$(dirname "$dest")"
        [[ -d "$dir" ]] || install -d -m 0755 "$dir"
        [[ -e "$dest" ]] || { : >"$dest"; chmod 0644 "$dest"; }
        tail -c "+$((off + 1))" "$src" >>"$dest"
    fi
    data_write_offset "$offfile" "$inode" "$size"
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
