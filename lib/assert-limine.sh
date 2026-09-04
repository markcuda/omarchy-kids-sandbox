# shellcheck shell=bash
# lib/assert-limine.sh — omarchy-kids-assert's disk-only Limine locks
# (V6, issue #38). The dispatcher gates them before any path access.
# Not meant to be executed directly. See docs/assert.md.

limine_conf() { printf '%s/boot/limine.conf' "$(posture_root)"; }
# Three-way: "no Limine at all" is ok, not warn (review S11, docs/assert.md).
limine_editor_ok() {
  local f
  f="$(limine_conf)"
  if [[ ! -f "$f" ]]; then
    command -v limine >/dev/null 2>&1 && return 2 # Limine is installed; /boot not mounted?
    return 0                                      # not a Limine box: nothing to lock
  fi
  grep -qE '^editor_enabled:[[:space:]]*no[[:space:]]*$' "$f"
}
limine_editor_fix() {
  local f tmp
  f="$(limine_conf)"
  [[ -f "$f" ]] || return 0
  # Temp-file-then-rename, never truncate-then-write (review S5).
  tmp="$(mktemp "$(dirname "$f")/.limine.conf.XXXXXX")" || return 1
  # `|| true`: grep -v on a single-matching-line file exits 1 with no
  # output, which used to delete the temp file and FAIL forever (review §2.10).
  {
    printf 'editor_enabled: no\n'
    grep -vE '^editor_enabled:' "$f" || true
  } >"$tmp" ||
    {
      rm -f "$tmp"
      return 1
    }
  chmod --reference="$f" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  mv -f "$tmp" "$f"
}

# A pre-Kids-Mode Snapper snapshot boots a frozen UKI with none of its
# locks; MAX_SNAPSHOT_ENTRIES=0 hides it from the Limine menu.
# machine.conf's boot.snapshot_entries (docs/conf.md) picks hide/show.
limine_default() { printf '%s/etc/default/limine' "$(posture_root)"; }
LIMINE_SNAPSHOTS_MARKER='# omarchy-kids: was MAX_SNAPSHOT_ENTRIES='

boot_snapshot_entries_mode() {
  local mode
  mode="$(conf_get "$MACHINE_CONF" boot.snapshot_entries 2>/dev/null || true)"
  [[ "$mode" == "show" ]] && {
    echo show
    return
  }
  echo hide
}

# limine_snapshots_marker_value FILE — the value remembered in our own
# comment line, if any (the value MAX_SNAPSHOT_ENTRIES held before we
# first set it to 0).
limine_snapshots_marker_value() {
  local f="$1" line
  line="$(grep -F "$LIMINE_SNAPSHOTS_MARKER" "$f" 2>/dev/null | tail -n1 || true)"
  [[ -n "$line" ]] && printf '%s' "${line#"$LIMINE_SNAPSHOTS_MARKER"}"
}

limine_snapshots_ok() {
  local f
  f="$(limine_default)"
  [[ -f "$f" ]] || return 2 # no /etc/default/limine here (not a Limine box)
  case "$(boot_snapshot_entries_mode)" in
    hide) grep -qxF 'MAX_SNAPSHOT_ENTRIES=0' "$f" ;;
    show) ! grep -qxF 'MAX_SNAPSHOT_ENTRIES=0' "$f" ;;
  esac
}

limine_snapshots_fix() {
  local f tmp mode
  f="$(limine_default)"
  [[ -f "$f" ]] || return 0
  mode="$(boot_snapshot_entries_mode)"
  # Same directory, then rename (review S5) -- see limine_editor_fix.
  tmp="$(mktemp "$(dirname "$f")/.limine.default.XXXXXX")" || return 1
  case "$mode" in
    hide)
      local old="" have_marker=0
      grep -qF "$LIMINE_SNAPSHOTS_MARKER" "$f" && have_marker=1
      if [[ "$have_marker" -eq 0 ]]; then
        old="$(grep -E '^MAX_SNAPSHOT_ENTRIES=' "$f" | tail -n1 || true)"
        old="${old#MAX_SNAPSHOT_ENTRIES=}"
      fi
      {
        grep -vE "^MAX_SNAPSHOT_ENTRIES=|^${LIMINE_SNAPSHOTS_MARKER}" "$f" || true
        if [[ "$have_marker" -eq 1 ]]; then
          grep -F "$LIMINE_SNAPSHOTS_MARKER" "$f"
        elif [[ -n "$old" ]]; then
          printf '%s%s\n' "$LIMINE_SNAPSHOTS_MARKER" "$old"
        fi
        printf 'MAX_SNAPSHOT_ENTRIES=0\n'
      } >"$tmp" || {
        rm -f "$tmp"
        return 1
      }
      ;;
    show)
      local old
      old="$(limine_snapshots_marker_value "$f")"
      {
        grep -vE "^MAX_SNAPSHOT_ENTRIES=|^${LIMINE_SNAPSHOTS_MARKER}" "$f" || true
        if [[ -n "$old" ]]; then printf 'MAX_SNAPSHOT_ENTRIES=%s\n' "$old"; fi
        true
      } >"$tmp" || {
        rm -f "$tmp"
        return 1
      }
      ;;
  esac
  chmod --reference="$f" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
  mv -f "$tmp" "$f" || {
    rm -f "$tmp"
    return 1
  }
  # Only a real run (never this dev checkout's tests, per AGENTS.md rule 8)
  # has an empty posture_root; limine-snapper-sync also may not be
  # installed at all (no Limine, no Snapper) -- either way, nothing to do.
  if [[ -z "$(posture_root)" ]] && command -v limine-snapper-sync >/dev/null 2>&1; then
    limine-snapper-sync
  fi
  return 0
}
