# shellcheck shell=bash
# lib/kids.sh -- shared helpers formerly duplicated across bin/omarchy-kids-*
# commands: dry-run preview, band/home-dir lookups, LUKS/stat wrappers, the
# sibling-binary resolver, the kid roster, portal entries, and the exit/ask
# modal's pidfile guard. Not meant to be executed directly; source it.

# is_root -- the one uid check in this package. No environment override:
# nothing a kid's session can set may decide whether a root check happens
# (AGENTS.md, "The trust boundary").
is_root() { [[ "$(id -u)" == "0" ]]; }

# KIDS_PY -- build-time constant, never an environment read (AGENTS.md).
# shellcheck disable=SC2034 # read by every sourcing command as "$KIDS_PY", not here
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

# VALID_BANDS -- Appendix B's four age bands, in order, declared once
# (previously six duplicated copies, where `13+` vs `13plus` had drifted).
# shellcheck disable=SC2034 # read by the sourcing command, not here
VALID_BANDS=("3-5" "6-8" "9-12" "13+")

# is_in NEEDLE [HAYSTACK...] -- is NEEDLE one of the rest.
is_in() {
    local needle="$1" x
    shift
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# is_valid_band BAND — is BAND one of them.
is_valid_band() { is_in "$1" "${VALID_BANDS[@]}"; }

# group_for_band BAND -- the Unix group for a provisioned band (Appendix
# C). Accepts both "13+" and "13plus" (a Chromium policy filename can't
# hold a '+').
group_for_band() {
    case "$1" in
        3-5) echo omarchy-kids-3-5 ;;
        6-8) echo omarchy-kids-6-8 ;;
        9-12) echo omarchy-kids-9-12 ;;
        13+ | 13plus) echo omarchy-kids-13plus ;;
        *) return 1 ;;
    esac
}

# home_dir_for ACCOUNT -- ACCOUNT's home under $HOME_ROOT (a scratch
# prefix in tests, empty by default).
home_dir_for() { printf '%s/home/%s\n' "${OMARCHY_KIDS_HOME_ROOT:-}" "$1"; }

# account_home ACCOUNT -- the real home via getent, else home_dir_for's guess.
account_home() {
    local home
    if command -v getent >/dev/null 2>&1; then
        home="$(getent passwd "$1" 2>/dev/null | cut -d: -f6)"
        [[ -n "$home" ]] && { printf '%s\n' "$home"; return 0; }
    fi
    home_dir_for "$1"
}

# parent_home_dir MACHINE_CONF -- the parent's home, or 1 when no parent is recorded.
parent_home_dir() {
    local parent
    parent="$(conf_get "$1" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    account_home "$parent"
}

# detect_luks_device [EXPLICIT] -- EXPLICIT wins, then
# $OMARCHY_KIDS_LUKS_DEVICE, then a best-effort lsblk scan.
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

# file_stat FMT FILE -- GNU/BSD stat(1) wrapper, GNU tried first (issue #49, docs/assert.md).
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

# kids_bin NAME DIR -- sibling command NAME, always DIR/bin/omarchy-kids-
# NAME. DIR is the caller's own resolved prefix, so on an installed box
# this *is* /usr/bin; a /usr/bin fallback would only hide "not installed
# yet" behind whatever the package happens to have put there. No
# environment override (AGENTS.md, "The trust boundary").
kids_bin() {
    printf '%s/bin/omarchy-kids-%s\n' "$2" "$1"
}

# first_field KEY TEXT -- value of the first "KEY=<value>" line. One awk
# pass, never `sed ... | head -1`: under `set -o pipefail` that returns
# 141 as soon as sed hasn't finished writing, aborting a caller's `set -e`.
first_field() {
    awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' <<<"$2"
}

# kids_band_field CONF_BIN BAND KEY -- one value out of `CONF_BIN band
# BAND` (Appendix C's per-band defaults).
kids_band_field() {
    local out
    out="$("$1" band "$2")" || return 1
    first_field "$3" "$out"
}

# kids_list DIR -- one provisioned account per line, every "*.conf"
# basename. Glob, not `ls`, so an empty directory yields nothing.
kids_list() {
    local dir="$1" f
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.conf; do
        [[ -e "$f" ]] || continue
        basename "$f" .conf
    done
}

# portal_conf_entries DIR [EXCLUDE] -- one "account<TAB>name<TAB>avatar"
# line per kid, for theme.conf.user. EXCLUDE drops the account being
# removed while it's still on disk.
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

# launched_by_a_human -- a person driving this, not a script: the app
# entry sets OMARCHY_KIDS_LAUNCHED_BY, or a tty on stdin+stdout. Only
# turns the DRY_RUN=1 default OFF for the two interactive commands
# (AGENTS.md rule 8) -- the screen the parent confirms is the confirmation.
launched_by_a_human() {
    [[ -n "${OMARCHY_KIDS_LAUNCHED_BY:-}" ]] && return 0   # the .desktop entry
    [[ -t 0 && -t 1 ]]                                     # a terminal
}

is_known_kid() { [[ -f "$2/$1.conf" ]]; }

# --- shared TUI validators/labels: each prints the one-line reason
# lib/tui.sh shows under the field, and returns 1.

# validate_budget_minutes VALUE -- Appendix B's budget_min range.
validate_budget_minutes() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 1440)) && return 0
    echo "A number of minutes, 1 to 1440."
    return 1
}

# validate_lights_out VALUE -- Appendix B's lights_out, 24-hour HH:MM.
validate_lights_out() {
    [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && return 0
    echo "24-hour time, like 19:30."
    return 1
}

# friendly_web_mode MODE -- R-WEB-3's three modes, in a parent's words.
friendly_web_mode() {
    case "$1" in
        none) echo "No browser" ;;
        garden) echo "Only sites you choose" ;;
        filtered) echo "Filtered open web" ;;
        *) echo "$1" ;;
    esac
}

# modal_already_open PIDFILE -- true if PIDFILE names a still-live process
# whose /proc comm is quickshell. Not a `pgrep -f` substring match on argv:
# a kid could start any process containing that string and wedge it shut.
modal_already_open() {
    local pidfile="$1" pid comm=""
    [[ -r "$pidfile" ]] || return 1
    IFS= read -r pid <"$pidfile" || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r "/proc/$pid/comm" ]] && IFS= read -r comm <"/proc/$pid/comm"
    [[ -z "$comm" || "$comm" == quickshell* ]]
}

# modal_write_pid PIDFILE [PID] -- records PID ($$, or $! for a
# backgrounded caller) as the one holding the modal open.
modal_write_pid() { printf '%s\n' "${2:-$$}" >"$1"; }

# modal_close PIDFILE -- ends the modal, if PIDFILE's owner is still the
# process that wrote it. Never `pkill -f` on an argv substring.
modal_close() {
    local pidfile="$1" pid
    modal_already_open "$pidfile" || { rm -f "$pidfile"; return 0; }
    IFS= read -r pid <"$pidfile" || return 0
    [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null
    rm -f "$pidfile"
    return 0
}
