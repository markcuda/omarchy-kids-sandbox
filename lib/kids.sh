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

# is_root — the one uid check in this package (docs/style.md §6). No
# environment override anywhere: nothing a kid's session can set may
# decide whether a root check happens (AGENTS.md, "The trust boundary";
# review §3.6).
is_root() { [[ "$(id -u)" == "0" ]]; }

# KIDS_PY — the interpreter for this package's lib/*.py helpers. A
# build-time constant, never an environment read: PKGBUILD rewrites this
# one line to the absolute /usr/bin/python3 at package time, and a
# checkout resolves python3 from PATH so the tests run on a dev box
# (AGENTS.md, "The trust boundary"). Assigned unconditionally so an
# exported KIDS_PY cannot win.
KIDS_PY=python3

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

# VALID_BANDS — Appendix B's four age bands, in order, declared once.
# Six commands each carried their own copy (review §1.7); a fifth band
# would have had to be added in six places, and `13+` vs `13plus` had
# already drifted once.
# shellcheck disable=SC2034 # read by the sourcing command, not here
VALID_BANDS=("3-5" "6-8" "9-12" "13+")

# is_valid_band BAND — is BAND one of them.
is_valid_band() {
    local b="$1" v
    for v in "${VALID_BANDS[@]}"; do [[ "$v" == "$b" ]] && return 0; done
    return 1
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
# format letter: "a" (permission bits), "G" (group name), "i" (inode)
# or "u" (owner uid).
file_stat() {
    local fmt="$1" file="$2"
    if stat --version >/dev/null 2>&1; then
        stat -c "%${fmt}" "$file" 2>/dev/null || true
        return 0
    fi
    case "$fmt" in
        a) stat -f '%Lp' "$file" 2>/dev/null || true ;;
        G) stat -f '%Sg' "$file" 2>/dev/null || true ;;
        i) stat -f '%i' "$file" 2>/dev/null || true ;;
        u) stat -f '%u' "$file" 2>/dev/null || true ;;
        *) return 1 ;;
    esac
}

# kids_bin NAME DIR — resolves the sibling command NAME's binary:
# DIR/bin/omarchy-kids-NAME when that's executable (a dev checkout, DIR
# being the caller's own `readlink -f "$0"`), else the absolute installed
# path. No environment override: a kid's session may invoke any of these,
# so nothing from the environment may choose what runs (AGENTS.md, "The
# trust boundary"; review §2.1, §3.6).
kids_bin() {
    local name="$1" dir="$2" candidate
    candidate="$dir/bin/omarchy-kids-$name"
    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
    else
        printf '%s\n' "/usr/bin/omarchy-kids-$name"
    fi
}

# first_field KEY TEXT — the value of the first "KEY=<value>" line in
# TEXT. One awk pass, never `sed ... | head -1`: head closes the pipe
# after the first line, so under `set -o pipefail` the pipeline returns
# 141 as soon as sed has not finished writing -- and every caller is a
# bare assignment under `set -e`, which would abort `provision add`
# mid-way (review §2.7).
first_field() {
    awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' <<<"$2"
}

# kids_band_field CONF_BIN BAND KEY — one value out of `omarchy-kids-conf
# band BAND` (Appendix C's per-band defaults). Prints nothing and returns
# 1 if that band cannot be read; the caller decides how loudly to fail.
kids_band_field() {
    local out
    out="$("$1" band "$2")" || return 1
    first_field "$3" "$out"
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

# launched_by_a_human — is a person driving this, rather than a script?
# The app entry (desktop/omarchy-kids.desktop) says so outright; a tty on
# both stdin and stdout is the other case. Only ever turns the DRY_RUN=1
# default OFF for the two interactive commands (AGENTS.md rule 8), which
# is why an env var may say it: the screen the parent confirms is the
# confirmation.
launched_by_a_human() {
    [[ -n "${OMARCHY_KIDS_LAUNCHED_BY:-}" ]] && return 0   # the .desktop entry
    [[ -t 0 && -t 1 ]]                                     # a terminal
}

# is_known_kid ACCOUNT KIDS_DIR — is there a provisioned profile for it.
is_known_kid() { [[ -f "$2/$1.conf" ]]; }

# --- shared TUI validators/labels (review §1.7: byte-identical copies in
# bin/omarchy-kids-panel and bin/omarchy-kids-wizard). Each prints the
# one-line reason lib/tui.sh shows under the field, and returns 1.

# validate_budget_minutes VALUE — Appendix B's budget_min range.
validate_budget_minutes() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 1440)) && return 0
    echo "A number of minutes, 1 to 1440."
    return 1
}

# validate_lights_out VALUE — Appendix B's lights_out, 24-hour HH:MM.
validate_lights_out() {
    [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && return 0
    echo "24-hour time, like 19:30."
    return 1
}

# friendly_web_mode MODE — R-WEB-3's three modes, in a parent's words.
friendly_web_mode() {
    case "$1" in
        none) echo "No browser" ;;
        garden) echo "Only sites you choose" ;;
        filtered) echo "Filtered open web" ;;
        *) echo "$1" ;;
    esac
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

# modal_write_pid PIDFILE [PID] — records PID (default: this process,
# for a caller that execs the modal) as the one holding the modal open,
# for modal_already_open to find. A caller that starts the modal in the
# background passes $! instead.
modal_write_pid() { printf '%s\n' "${2:-$$}" >"$1"; }

# modal_close PIDFILE — ends the modal PIDFILE names, if it is still the
# process that wrote it. Never `pkill -f` on an argv substring (review
# §1.9/§2.6).
modal_close() {
    local pidfile="$1" pid
    modal_already_open "$pidfile" || { rm -f "$pidfile"; return 0; }
    IFS= read -r pid <"$pidfile" || return 0
    [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null
    rm -f "$pidfile"
    return 0
}
