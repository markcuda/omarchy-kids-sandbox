# shellcheck shell=bash
# lib/conf.sh -- key=value file helpers for /etc/omarchy-kids/kids/<account>.conf
# and similar files (R-BUILD-5). One KEY=VALUE per line, no spaces around
# '='; '#' starts a full-line comment. Comments and line order are
# preserved by every write here -- conf_set only ever touches the one
# line it is asked to touch, and conf_del only removes lines for its key.

# conf_get FILE KEY -- prints KEY's value (last match wins) and returns 0,
# or returns 1 with nothing printed if missing.
conf_get() {
    local file="$1" key="$2" line k v found=1
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        k="${line%%=*}"
        [[ "$k" == "$key" ]] || continue
        v="${line#*=}"
        found=0
    done < "$file"
    [[ $found == 0 ]] && printf '%s\n' "$v"
    return $found
}

# conf_set FILE KEY VALUE -- replaces KEY's line in place, else appends.
# Creates the parent dir/file if missing; mode stays 0644 (spec §5.1).
conf_set() {
    local file="$1" key="$2" value="$3" dir tmp line k replaced=0
    dir="$(dirname "$file")"
    [[ -d "$dir" ]] || install -d -m 0755 "$dir"
    tmp="$(mktemp "${file}.XXXXXX")"
    if [[ -e "$file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                ''|'#'*) printf '%s\n' "$line" >>"$tmp"; continue ;;
            esac
            k="${line%%=*}"
            if [[ "$k" == "$key" && $replaced == 0 ]]; then
                printf '%s=%s\n' "$key" "$value" >>"$tmp"
                replaced=1
            else
                printf '%s\n' "$line" >>"$tmp"
            fi
        done < "$file"
    fi
    if [[ $replaced == 0 ]]; then
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
    fi
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
}

# conf_del FILE KEY -- removes every line setting KEY. A no-op if missing.
conf_del() {
    local file="$1" key="$2" tmp line k
    [[ -e "$file" ]] || return 0
    tmp="$(mktemp "${file}.XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|'#'*) printf '%s\n' "$line" >>"$tmp"; continue ;;
        esac
        k="${line%%=*}"
        [[ "$k" == "$key" ]] && continue
        printf '%s\n' "$line" >>"$tmp"
    done < "$file"
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
}
