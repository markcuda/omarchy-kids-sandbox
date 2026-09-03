# shellcheck shell=bash
# lib/kids.sh — the small helpers seven-plus bin/omarchy-kids-* commands
# each carried their own copy of (review §3/§7): dry-run preview, band/
# home-dir lookups, LUKS/stat wrappers, the sibling-binary resolver, the
# kid roster, portal entries, and the exit/ask modal's pidfile guard. One
# home so they can't drift the way group_for_band and portal_conf_entries
# already had (13plus vs 13+, a silently dropped EXCLUDE argument).
#
# Not meant to be executed directly; source it from a command:
#   source "$DIR/lib/kids.sh"

# run CMD [ARG...] — DRY_RUN=1 (default) prints the shell-quoted command
# instead of running it; DRY_RUN=0 (or --apply) runs it for real.
run() {
    if [[ "$DRY_RUN" == "0" ]]; then
        "$@"
    else
        printf '  [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    fi
}

# group_for_band BAND — the Unix group for a provisioned band (Appendix
# C). Accepts both "13+" (Appendix B's own spelling) and "13plus" (a
# Chromium policy filename can't hold a '+'); prints nothing and returns
# 1 on an unknown band so the caller decides whether that's fatal.
group_for_band() {
    case "$1" in
        3-5) echo omarchy-kids-3-5 ;;
        6-8) echo omarchy-kids-6-8 ;;
        9-12) echo omarchy-kids-9-12 ;;
        13+ | 13plus) echo omarchy-kids-13plus ;;
        *) return 1 ;;
    esac
}

# home_dir_for ACCOUNT — ACCOUNT's home under $HOME_ROOT (empty by
# default, a scratch prefix in tests).
home_dir_for() { printf '%s/home/%s\n' "$HOME_ROOT" "$1"; }

# parent_home_dir MACHINE_CONF — the parent account's real home
# (`getent`) when this box has one, else the same $HOME_ROOT-prefixed
# guess home_dir_for gives every other account. Empty and non-zero if
# MACHINE_CONF has no "parent=" line.
parent_home_dir() {
    local machine_conf="$1" parent home
    parent="$(conf_get "$machine_conf" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    if command -v getent >/dev/null 2>&1; then
        home="$(getent passwd "$parent" 2>/dev/null | cut -d: -f6)"
        [[ -n "$home" ]] && { printf '%s\n' "$home"; return 0; }
    fi
    home_dir_for "$parent"
}

# detect_luks_device [EXPLICIT] — EXPLICIT wins, then
# $OMARCHY_KIDS_LUKS_DEVICE, then a best-effort lsblk scan for the first
# crypto_LUKS block device. Prints nothing and returns 1 if none found.
detect_luks_device() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then printf '%s\n' "$explicit"; return 0; fi
    if [[ -n "${OMARCHY_KIDS_LUKS_DEVICE:-}" ]]; then printf '%s\n' "$OMARCHY_KIDS_LUKS_DEVICE"; return 0; fi
    if command -v lsblk >/dev/null 2>&1; then
        local dev
        dev="$(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2=="crypto_LUKS"{print "/dev/"$1; exit}')"
        [[ -n "$dev" ]] && { printf '%s\n' "$dev"; return 0; }
    fi
    return 1
}

# file_stat FMT FILE — one stat(1) wrapper for GNU and BSD stat, since a
# BSD-first form silently misreads on Linux (`stat -f` there means
# "filesystem status", not BSD's "format", seen live 2026-09-02 re-fixing
# an already-correct chromium lock every run). FMT is a GNU stat(1)
# format letter: "a" (permission bits) or "G" (group name).
file_stat() {
    local fmt="$1" file="$2"
    if stat --version >/dev/null 2>&1; then
        stat -c "%${fmt}" "$file" 2>/dev/null || true
        return 0
    fi
    case "$fmt" in
        a) stat -f '%Lp' "$file" 2>/dev/null || true ;;
        G) stat -f '%Sg' "$file" 2>/dev/null || true ;;
        *) return 1 ;;
    esac
}

# kids_bin NAME DIR — resolves the sibling command NAME's binary: an env
# override (OMARCHY_KIDS_<NAME>_BIN), else DIR/bin/omarchy-kids-NAME when
# that's executable (a dev checkout), else the bare command on PATH (an
# installed package).
kids_bin() {
    local name="$1" dir="$2" var override candidate
    var="OMARCHY_KIDS_$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')_BIN"
    override="${!var:-}"
    if [[ -n "$override" ]]; then printf '%s\n' "$override"; return 0; fi
    candidate="$dir/bin/omarchy-kids-$name"
    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
    else
        printf '%s\n' "omarchy-kids-$name"
    fi
}

# kids_list DIR — one provisioned account per line: every "*.conf"
# basename under DIR (a kid's own $KIDS_DIR). Glob, not `ls`, so an empty
# directory yields nothing rather than a literal "*.conf".
kids_list() {
    local dir="$1" f
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.conf; do
        [[ -e "$f" ]] || continue
        basename "$f" .conf
    done
}

# portal_conf_entries DIR [EXCLUDE] — one "account<TAB>name<TAB>avatar"
# line per kid under DIR, for theme.conf.user (posture_portal_conf_text).
# EXCLUDE, when given, drops that one account — the account being
# removed, still on disk when the caller has to rebuild the file.
portal_conf_entries() {
    local dir="$1" exclude="${2:-}" f account name avatar
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.conf; do
        [[ -e "$f" ]] || continue
        account="$(basename "$f" .conf)"
        [[ -n "$exclude" && "$account" == "$exclude" ]] && continue
        name="$(conf_get "$f" name 2>/dev/null || true)"
        avatar="$(conf_get "$f" avatar 2>/dev/null || true)"
        printf '%s\t%s\t%s\n' "$account" "$name" "$avatar"
    done
}

# modal_already_open PIDFILE — true if PIDFILE names a still-live process
# whose /proc comm is quickshell. A pidfile the modal writes itself
# (modal_write_pid), not a `pgrep -f` substring match on argv: a kid
# could start any process containing that string and wedge the modal
# shut forever (review §1.9).
modal_already_open() {
    local pidfile="$1" pid comm=""
    [[ -r "$pidfile" ]] || return 1
    IFS= read -r pid <"$pidfile" || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r "/proc/$pid/comm" ]] && IFS= read -r comm <"/proc/$pid/comm"
    [[ -z "$comm" || "$comm" == quickshell* ]]
}

# modal_write_pid PIDFILE — records this process as the one holding the
# modal open, for modal_already_open to find.
modal_write_pid() { printf '%s\n' "$$" >"$1"; }
