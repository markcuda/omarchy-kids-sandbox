# shellcheck shell=bash
# lib/check-web.sh — omarchy-kids-check's Web section. Sourced by the
# dispatcher; not meant to be executed directly. docs/check.md.

run_web_section() {
  local dir cf bt group owner_group any=0
  dir="$(chromium_dir)"
  if [[ ! -d "$dir" ]]; then
    add_result Web "web:policy" skip "no $dir on this box; nothing to check"
    return
  fi
  for cf in "$dir"/omarchy-kids-*.json; do
    [[ -e "$cf" ]] || continue
    any=1
    bt="$(basename "$cf")"
    bt="${bt#omarchy-kids-}"
    bt="${bt%.json}"
    group="$(group_for_band "$bt" 2>/dev/null || true)"

    if chromium_ok "$cf" "$bt"; then
      add_result Web "web:mode:$bt" pass "$cf is mode 0640 (R-WEB-1)"
    else
      add_result Web "web:mode:$bt" fail "$cf is not mode 0640 — run 'omarchy-kids-assert' (R-WEB-1)"
    fi

    # Group ownership: root-only check, same reasoning as the
    # chromium-policy lock (docs/check.md's "Web" section).
    owner_group="$(file_stat G "$cf")"
    if [[ "$EUID" != 0 ]]; then
      add_result Web "web:owner:$bt" skip "not checked as non-root — a real run of this check is always root, at which point the file's group is already correct by construction (R-WEB-1)"
    elif [[ -z "$owner_group" ]]; then
      add_result Web "web:owner:$bt" warn "cannot verify: could not read $cf's group owner on this box"
    elif [[ -n "$group" && "$owner_group" == "$group" ]]; then
      add_result Web "web:owner:$bt" pass "$cf is group-owned by $group (R-WEB-1)"
    else
      add_result Web "web:owner:$bt" fail "$cf's group owner is '$owner_group', expected '$group' — run 'omarchy-kids-web install' (R-WEB-1)"
    fi

    if grep -q '"DnsOverHttpsMode"[[:space:]]*:[[:space:]]*"secure"' "$cf" 2>/dev/null; then
      add_result Web "web:doh:$bt" pass "$cf sets DnsOverHttpsMode: secure (R-WEB-2)"
    else
      add_result Web "web:doh:$bt" fail "$cf does not set DnsOverHttpsMode: secure (R-WEB-2)"
    fi
  done
  [[ "$any" == 1 ]] || add_result Web "web:policy" skip "no per-band policy files exist yet; nothing to check"
}
