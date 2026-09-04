# shellcheck shell=bash
# lib/boot-mode.sh -- the trusted machine boot setting (R-BOOTMODE-1,
# R-BOOTMODE-12). The reader owns validation so later root consumers cannot
# invent a second mode detector. Its paths are build-time constants: tests
# substitute them in a copied tree, never through the environment.

BOOT_MODE_MACHINE_CONF=/etc/omarchy-kids/machine.conf
# Every path that reads the mode to act on it, and every path that changes it, must hold this lock.
BOOT_MODE_LOCK=/run/omarchy-kids/boot-mode.lock
BOOT_MODE_LOCK_FD=9

boot_mode_valid() {
  [[ "$1" == disk || "$1" == portal ]]
}

boot_mode_dir_safe() {
  local dir="$1" mode
  [[ -d "$dir" && ! -L "$dir" ]] || return 1
  mode="$(file_stat a "$dir")"
  [[ "$mode" =~ ^7[0-5][0-5]$ ]] || return 1
  [[ "$(file_stat u "$dir")" == 0 ]] || return 1
  [[ "$(file_stat G "$dir")" == root ]] || return 1
}

boot_mode_file_safe() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  [[ "$(file_stat a "$file")" == 644 ]] || return 1
  [[ "$(file_stat u "$file")" == 0 ]] || return 1
  [[ "$(file_stat G "$file")" == root ]] || return 1
}

# boot_mode_scan FILE ALLOW_MISSING — validates the machine file and prints
# its one boot value. A missing key is allowed only while an explicit setter
# repairs an existing machine file.
boot_mode_scan() {
  local file="$1" allow_missing="$2" line key value mode="" count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '' | '#'*) continue ;;
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        [[ -n "$key" ]] || return 1
        if [[ "$key" == boot ]]; then
          count=$((count + 1))
          mode="$value"
        fi
        ;;
      *) return 1 ;;
    esac
  done <"$file"

  if [[ "$count" -eq 0 ]]; then
    [[ "$allow_missing" == 1 ]]
    return $?
  fi
  [[ "$count" -eq 1 ]] || return 1
  boot_mode_valid "$mode" || return 1
  printf '%s\n' "$mode"
}

boot_mode_get() {
  boot_mode_dir_safe "$(dirname "$BOOT_MODE_MACHINE_CONF")" || return 1
  boot_mode_file_safe "$BOOT_MODE_MACHINE_CONF" || return 1
  boot_mode_scan "$BOOT_MODE_MACHINE_CONF" 0
}

boot_mode_lock_acquire() {
  local wait_seconds="${1:-}" file="$BOOT_MODE_LOCK" dir
  dir="$(dirname "$file")"

  if [[ -e "$dir" || -L "$dir" ]]; then
    boot_mode_dir_safe "$dir" || return 1
  else
    install -d -m 0755 "$dir" || return 1
    chown root:root "$dir" || return 1
    boot_mode_dir_safe "$dir" || return 1
  fi

  if [[ -e "$file" || -L "$file" ]]; then
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ "$(file_stat u "$file")" == 0 ]] || return 1
    [[ "$(file_stat G "$file")" == root ]] || return 1
  else
    (umask 077 && : >>"$file") || return 1
    [[ "$(file_stat u "$file")" == 0 ]] || return 1
    [[ "$(file_stat G "$file")" == root ]] || return 1
  fi
  chmod 0600 "$file" || return 1

  exec 9>>"$file" || return 1
  if [[ -n "$wait_seconds" ]]; then
    flock -w "$wait_seconds" "$BOOT_MODE_LOCK_FD" || {
      exec 9>&-
      return 1
    }
  else
    flock "$BOOT_MODE_LOCK_FD" || {
      exec 9>&-
      return 1
    }
  fi
}

boot_mode_lock_release() {
  flock -u "$BOOT_MODE_LOCK_FD" 2>/dev/null || true
  exec 9>&-
}

boot_mode_set() {
  local requested="$1" file="$BOOT_MODE_MACHINE_CONF" dir tmp line key replaced=0
  boot_mode_valid "$requested" || return 2
  is_root || {
    echo "omarchy-kids-conf: setting machine boot mode requires root" >&2
    return 1
  }

  dir="$(dirname "$file")"
  if [[ -e "$dir" || -L "$dir" ]]; then
    boot_mode_dir_safe "$dir" || {
      echo "omarchy-kids-conf: refusing unsafe machine.conf directory" >&2
      return 1
    }
  else
    install -d -m 0755 "$dir" || return 1
    boot_mode_dir_safe "$dir" || return 1
  fi

  if [[ -e "$file" || -L "$file" ]]; then
    boot_mode_file_safe "$file" || {
      echo "omarchy-kids-conf: refusing unsafe machine.conf" >&2
      return 1
    }
    boot_mode_scan "$file" 1 >/dev/null || {
      echo "omarchy-kids-conf: refusing invalid machine.conf" >&2
      return 1
    }
  fi

  tmp="$(mktemp "$dir/.machine.conf.XXXXXX")" || return 1
  if ! {
    if [[ -f "$file" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
          *=*)
            key="${line%%=*}"
            if [[ "$key" == boot && "$replaced" -eq 0 ]]; then
              printf 'boot=%s\n' "$requested"
              replaced=1
            else
              printf '%s\n' "$line"
            fi
            ;;
          *) printf '%s\n' "$line" ;;
        esac
      done <"$file"
    fi
    [[ "$replaced" -eq 1 ]] || printf 'boot=%s\n' "$requested"
  } >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if ! chmod 0644 "$tmp" || ! chown root:root "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  [[ "$(boot_mode_get 2>/dev/null || true)" == "$requested" ]]
}
