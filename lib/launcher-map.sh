# shellcheck shell=bash
# lib/launcher-map.sh — root-written launcher maps for the Level 1/2 tile grid.
# The map is the execution authority; the kid's runtime JSON is display-only.

launcher_map_path() { printf '%s/launchers/%s.json' "$ETC" "$1"; }

# launcher_map_find_desktop ID PKG — finds only package-owned desktop entries.
launcher_map_find_desktop() {
  local id="$1" pkg="$2" sysroot dir f base needle_id needle_pkg base_lc
  sysroot="${OMARCHY_KIDS_ROOT:-}"
  needle_id="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
  needle_pkg="${pkg#aur:}"
  needle_pkg="$(printf '%s' "$needle_pkg" | tr '[:upper:]' '[:lower:]')"
  for dir in "$sysroot/usr/share/applications" "$sysroot/usr/local/share/applications"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.desktop; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f" .desktop)"
      base_lc="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
      if [[ "$base_lc" == *"$needle_id"* || (-n "$needle_pkg" && "$base_lc" == *"$needle_pkg"*) ]]; then
        printf '%s\n' "$f"
        return 0
      fi
    done
  done
  return 1
}

# launcher_map_exec_json FILE — fixed absolute argv from a trusted desktop entry.
launcher_map_exec_json() {
  "$KIDS_PY" "$LIB/conf.py" desktop-argv "$1"
}

# launcher_map_bare_json ID — resolves a pack fallback while root owns the map.
launcher_map_bare_json() {
  local executable
  executable="$(command -v "$1" 2>/dev/null || true)"
  [[ "$executable" == /* && -x "$executable" ]] || return 1
  jq -n --arg executable "$executable" '[$executable]'
}

# launcher_map_render ACCOUNT OUTPUT — derives one map from the root profile.
launcher_map_render() {
  local account="$1" output="$2" band level web allowlist pack id meta label pkg desktop icon argv_json installed
  local entries
  local -a ids
  local sysroot="${OMARCHY_KIDS_ROOT:-}" apps_bin

  band="$(conf_get "$KIDS_DIR/$account.conf" band)"
  level="$("$CONF_BIN" get "$account" level)"
  web="$("$CONF_BIN" get "$account" web)"
  apps_bin="$(kids_bin apps "$DIR")"
  allowlist="$(OMARCHY_KIDS_ETC="$ETC" OMARCHY_KIDS_SHARE="$SHARE" "$apps_bin" allowlist "$account")"
  pack="$SHARE/packs/$band.toml"
  entries="$(mktemp)"

  IFS=',' read -ra ids <<<"$allowlist"
  for id in "${ids[@]+"${ids[@]}"}"; do
    [[ -n "$id" ]] || continue
    desktop=""
    if meta="$("$KIDS_PY" "$LIB/conf.py" pack-app "$pack" "$id" 2>/dev/null)"; then
      IFS=$'\t' read -r label pkg _web <<<"$meta"
    else
      # Extra ids have no pack row; desktop metadata still gives them a fixed tile.
      label="$id"
      pkg="$id"
    fi
    icon=""
    argv_json='[]'
    if desktop="$(launcher_map_find_desktop "$id" "$pkg")"; then
      icon="$(grep -m1 '^Icon=' "$desktop" | cut -d= -f2- || true)"
      argv_json="$(launcher_map_exec_json "$desktop" 2>/dev/null || echo '[]')"
    fi
    if [[ "$argv_json" == '[]' ]]; then
      argv_json="$(launcher_map_bare_json "$id" 2>/dev/null || echo '[]')"
    fi
    installed=false
    [[ "$argv_json" != '[]' ]] && installed=true
    jq -n --arg id "$id" --arg label "$label" --arg icon "$icon" --arg pkg "$pkg" \
      --argjson argv "$argv_json" --argjson installed "$installed" \
      '{id: $id, label: $label, icon: $icon, pkg: $pkg, installed: $installed, argv: $argv}' >>"$entries"
  done

  # Web uses the packaged command, so no browser command comes from the kid's PATH.
  if [[ "$web" != "none" && -r "$sysroot/etc/chromium/policies/managed/omarchy-kids-$band.json" ]]; then
    jq -n '{id: "chromium", label: "Web", icon: "chromium", pkg: "", installed: true,
      argv: ["/usr/bin/omarchy-kids-web", "launch"]}' >>"$entries"
  fi

  if [[ "$level" == "1" && "$band" != "3-5" ]]; then
    jq -n --arg band "$band" \
      '{id: "more-apps", label: "More apps", icon: "", pkg: "", installed: true,
        argv: ["/usr/bin/env", ("OMARCHY_KIDS_BAND=" + $band), "/usr/bin/quickshell", "-p",
          "/usr/share/omarchy-kids/plugins/shell.qml"]}' >>"$entries"
  fi

  if [[ "$band" == "9-12" || "$band" == "13+" ]]; then
    jq -n '{id: "kids-data", label: "What grown-ups see", icon: "", pkg: "", installed: true,
      argv: ["/usr/bin/omarchy-launch-floating-terminal-with-presentation",
        "/usr/bin/omarchy-kids-data", "mine"]}' >>"$entries"
  fi

  jq -s --arg account "$account" --arg band "$band" --arg level "$level" \
    '{account: $account, band: $band, level: $level, tiles: .}' "$entries" >"$output"
  rm -f "$entries"
}

# launcher_map_fix ACCOUNT — atomically writes the root-owned execution map.
launcher_map_fix() {
  local account="$1" dir stage
  dir="$(dirname "$(launcher_map_path "$account")")"
  install -d -m 0755 "$dir"
  stage="$(mktemp "$dir/.$account.XXXXXX")"
  launcher_map_render "$account" "$stage"
  chmod 0644 "$stage"
  chown root:root "$stage" 2>/dev/null || true
  mv -f "$stage" "$(launcher_map_path "$account")"
}

launcher_map_remove() { rm -f "$(launcher_map_path "$1")"; }

launcher_map_ok() {
  local account="$1" expected
  [[ "$(file_stat a "$(launcher_map_path "$account")" 2>/dev/null || true)" == 644 ]] || return 1
  expected="$(mktemp)"
  launcher_map_render "$account" "$expected"
  cmp -s "$expected" "$(launcher_map_path "$account")"
  local rc=$?
  rm -f "$expected"
  return "$rc"
}
