#!/bin/bash
# Mac-side release screenshot driver (docs/GOAL.md item 3; issue #103).
# One VM driver at a time. Never run this beside test/live/all or another VM scenario.
# Usage: scripts/media-driver.sh [--surface NAME] [THEME ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "${OMARCHY_KIDS_VM_DRIVER_LOCKED:-0}" != 1 ]]; then
  exec "$SCRIPT_DIR/vm-driver-lock" "$0" "$@"
fi
MEDIA_DIR="$REPO_ROOT/docs/media"
SURFACES=(portal launcher exit-modal ask times-up wifi-picker plugins-shelf wizard panel bar-module)
THEMES=()
SURFACE_FILTER=""
RUN_FAILED=0
THEMES_SAVED=0
THEME_DIRTY=0
ORIGINAL_OWNER_THEME=""
ORIGINAL_KID_THEME=""
ORIGINAL_KID_THEME_SOURCE=""
ORIGINAL_LIGHTS_OUT=""
ORIGINAL_LIGHTS_OUT_SOURCE=""
ORIGINAL_LIGHTS_OUT_WEEKEND=""
ORIGINAL_LIGHTS_OUT_WEEKEND_SOURCE=""
ORIGINAL_WIFI=""
ORIGINAL_WIFI_SOURCE=""
LIGHTS_OUT_DIRTY=0
LIGHTS_OUT_WEEKEND_DIRTY=0
WIFI_DIRTY=0
TIME_TIMER_STOPPED=0

usage() {
  cat <<'EOF'
Usage: scripts/media-driver.sh [--surface NAME] [THEME ...]

Capture every Kids Mode release surface under each named Omarchy theme.
With no themes, captures tokyo-night and catppuccin-latte. Images land in
docs/media/<surface>-<theme>.png.

  --surface NAME  Capture only one of: portal, launcher, exit-modal, ask,
                  times-up, wifi-picker, plugins-shelf, wizard, panel,
                  bar-module.
  -h, --help      Show this help.

The shared VM lock refuses a second driver and names the active run. This
driver changes the owner and test-kid themes, restarts SDDM, then restores
both themes. The bar widget must already be enabled; this script never changes
the parent's bar.
EOF
}

die() {
  echo "media-driver: $1" >&2
  exit "${2:-1}"
}

is_surface() {
  local wanted="$1" surface
  for surface in "${SURFACES[@]}"; do
    [[ "$surface" == "$wanted" ]] && return 0
  done
  return 1
}

while (($#)); do
  case "$1" in
    --surface)
      (($# >= 2)) || die "--surface needs a name (see --help)" 2
      SURFACE_FILTER="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --*) die "unknown option '$1' (see --help)" 2 ;;
    *)
      THEMES+=("$1")
      shift
      ;;
  esac
done

[[ -z "$SURFACE_FILTER" ]] || is_surface "$SURFACE_FILTER" ||
  die "unknown surface '$SURFACE_FILTER' (see --help)" 2
((${#THEMES[@]})) || THEMES=(tokyo-night catppuccin-latte)
for theme in "${THEMES[@]}"; do
  [[ "$theme" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die "unsafe theme name '$theme'" 2
done

mkdir -p "$MEDIA_DIR"
STAGE_DIR="$(mktemp -d "$MEDIA_DIR/.media-driver.XXXXXX")"
export LIVE_OUT_DIR="$STAGE_DIR"
# shellcheck source=test/live/lib.sh
source "$REPO_ROOT/test/live/lib.sh"
# config.env may name the acceptance-report directory; this driver always stages beside docs/media.
export LIVE_OUT_DIR="$STAGE_DIR"

shell_quote() { printf '%q' "$1"; }

apply_owner_theme() {
  local theme_q
  theme_q="$(shell_quote "$1")"
  vm "export OMARCHY_PATH=/usr/share/omarchy; /usr/bin/omarchy-theme-set $theme_q >/dev/null"
}

apply_kid_theme() {
  local kid_q theme_q
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  theme_q="$(shell_quote "$1")"
  vmroot "env -i PATH=/usr/bin:/bin OMARCHY_PATH=/usr/share/omarchy /usr/bin/omarchy-kids-conf set $kid_q theme $theme_q >/dev/null"
}

unset_kid_setting() {
  local kid_q key_q
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  key_q="$(shell_quote "$1")"
  vmroot "env -i PATH=/usr/bin:/bin OMARCHY_PATH=/usr/share/omarchy /usr/bin/omarchy-kids-conf unset $kid_q $key_q >/dev/null"
}

kid_setting_source() {
  local kid_q key_q source
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  key_q="$(shell_quote "$1")"
  source="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf source $kid_q $key_q")" || return 1
  case "$source" in override | band | default) printf '%s\n' "$source" ;; *) return 1 ;; esac
}

refresh_portal() {
  local failed=0
  vmroot "env -i PATH=/usr/bin:/bin OMARCHY_PATH=/usr/share/omarchy /usr/bin/omarchy-kids-assert >/dev/null" || failed=1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/systemctl restart sddm" || failed=1
  assert_greeter 60 || failed=1
  return "$failed"
}

restore_themes() {
  local failed=0
  ((THEMES_SAVED && THEME_DIRTY)) || return 0
  echo "Restoring themes"
  apply_owner_theme "$ORIGINAL_OWNER_THEME" || {
    echo "media-driver: could not restore owner theme '$ORIGINAL_OWNER_THEME'" >&2
    failed=1
  }
  if [[ "$ORIGINAL_KID_THEME_SOURCE" == override ]]; then
    apply_kid_theme "$ORIGINAL_KID_THEME" || {
      echo "media-driver: could not restore $LIVE_KID1_ACCOUNT theme '$ORIGINAL_KID_THEME'" >&2
      failed=1
    }
  else
    unset_kid_setting theme || {
      echo "media-driver: could not restore $LIVE_KID1_ACCOUNT's inherited theme" >&2
      failed=1
    }
  fi
  ((failed)) || THEME_DIRTY=0
  return "$failed"
}

settle_at_greeter() {
  local failed=0
  echo "Closing sessions and confirming the greeter"
  vmroot "env -i PATH=/usr/bin:/bin OMARCHY_PATH=/usr/share/omarchy /usr/bin/omarchy-kids-assert >/dev/null" || {
    echo "media-driver: omarchy-kids-assert failed during cleanup" >&2
    failed=1
  }
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/systemctl restart sddm" || {
    echo "media-driver: could not restart SDDM during cleanup" >&2
    failed=1
  }
  assert_no_session "$LIVE_KID1_ACCOUNT" 60 || {
    echo "media-driver: $LIVE_KID1_ACCOUNT still has a seat session after cleanup" >&2
    failed=1
  }
  assert_no_session "$LIVE_OWNER_ACCOUNT" 60 || {
    echo "media-driver: $LIVE_OWNER_ACCOUNT still has a seat session after cleanup" >&2
    failed=1
  }
  assert_greeter 60 || {
    echo "media-driver: cleanup could not confirm the SDDM greeter" >&2
    failed=1
  }
  return "$failed"
}

restore_transient_state() {
  local failed=0 kid_q value_q retick=0
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  if ((LIGHTS_OUT_DIRTY)); then
    if [[ "$ORIGINAL_LIGHTS_OUT_SOURCE" == override ]]; then
      value_q="$(shell_quote "$ORIGINAL_LIGHTS_OUT")"
      vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q lights_out $value_q >/dev/null"
    else
      unset_kid_setting lights_out
    fi &&
      LIGHTS_OUT_DIRTY=0 || failed=1
    retick=1
  fi
  if ((LIGHTS_OUT_WEEKEND_DIRTY)); then
    if [[ "$ORIGINAL_LIGHTS_OUT_WEEKEND_SOURCE" == override ]]; then
      value_q="$(shell_quote "$ORIGINAL_LIGHTS_OUT_WEEKEND")"
      vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q lights_out_weekend $value_q >/dev/null"
    else
      unset_kid_setting lights_out_weekend
    fi &&
      LIGHTS_OUT_WEEKEND_DIRTY=0 || failed=1
    retick=1
  fi
  if ((retick)); then
    vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-time-ledger tick >/dev/null" || failed=1
  fi
  if ((WIFI_DIRTY)); then
    if [[ "$ORIGINAL_WIFI_SOURCE" == override ]]; then
      value_q="$(shell_quote "$ORIGINAL_WIFI")"
      vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q wifi $value_q >/dev/null"
    else
      unset_kid_setting wifi
    fi &&
      WIFI_DIRTY=0 || failed=1
  fi
  if ((TIME_TIMER_STOPPED)); then
    vmroot "env -i PATH=/usr/bin:/bin /usr/bin/systemctl start omarchy-kids-time.timer" &&
      TIME_TIMER_STOPPED=0 || failed=1
  fi
  return "$failed"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if ! restore_transient_state; then status=1; fi
  if ! restore_themes; then status=1; fi
  if ! settle_at_greeter; then status=1; fi
  rm -rf "$STAGE_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

capture() {
  local surface="$1" theme="$2" name
  name="$surface-$theme"
  rm -f "$STAGE_DIR/$name.png" || return 1
  shot "$name" || return 1
  [[ -s "$STAGE_DIR/$name.png" ]] || {
    echo "media-driver: shot returned without $name.png" >&2
    return 1
  }
  mv -f "$STAGE_DIR/$name.png" "$MEDIA_DIR/$name.png" || return 1
  echo "saved docs/media/$name.png"
}

wait_vm_process() {
  local account_q pattern_q waited=0 deadline="${3:-30}"
  account_q="$(shell_quote "$1")"
  pattern_q="$(shell_quote "$2")"
  while ((waited < deadline)); do
    vmroot "env -i PATH=/usr/bin:/bin /usr/bin/pgrep -u $account_q -f $pattern_q >/dev/null" 2>/dev/null && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

start_in_session() {
  local account="$1" process_pattern="$2" command="$3"
  local account_q pattern_q command_q payload payload_q
  account_q="$(shell_quote "$account")"
  pattern_q="$(shell_quote "$process_pattern")"
  command_q="$(shell_quote "$command")"
  payload="acct=$account_q; pid=\$(pgrep -u \"\$acct\" -f $pattern_q | head -1); [ -n \"\$pid\" ] || exit 1; home=\$(getent passwd \"\$acct\" | cut -d: -f6); [ -n \"\$home\" ] || exit 1; env_args=(\"HOME=\$home\" \"USER=\$acct\" \"LOGNAME=\$acct\" \"OMARCHY_PATH=/usr/share/omarchy\"); for v in WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID DBUS_SESSION_BUS_ADDRESS; do value=\$(tr '\\0' '\\n' <\"/proc/\$pid/environ\" | sed -n \"s/^\$v=//p\" | head -1); [ -z \"\$value\" ] || env_args+=(\"\$v=\$value\"); done; runuser -u \"\$acct\" -- env \"\${env_args[@]}\" setsid /bin/bash -c $command_q >/tmp/omarchy-kids-media-driver.log 2>&1 </dev/null &"
  payload_q="$(shell_quote "$payload")"
  vmroot "env -i PATH=/usr/bin:/bin /bin/bash -c $payload_q"
}

prepare_kid() {
  portal_reset 45 || return 1
  portal_login "$LIVE_KID1_ACCOUNT" "$LIVE_KID1_PASSWORD" || return 1
  wait_kid_ready "$LIVE_KID1_ACCOUNT" 60
}

prepare_owner() {
  portal_reset 45 || return 1
  portal_login "$LIVE_OWNER_ACCOUNT" "$LIVE_OWNER_PASSWORD" || return 1
  wait_vm_process "$LIVE_OWNER_ACCOUNT" Hyprland 60 || return 1
  wait_vm_process "$LIVE_OWNER_ACCOUNT" omarchy-shell 60
}

shoot_portal() {
  local theme="$1"
  assert_greeter 30 || return 1
  capture portal "$theme"
}

shoot_launcher() {
  local theme="$1"
  prepare_kid || return 1
  capture launcher "$theme"
}

shoot_exit_modal() {
  local theme="$1"
  prepare_kid || return 1
  for _ in 1 2 3; do
    qmp key meta_l >/dev/null || return 1
    sleep 0.25
  done
  wait_vm_process "$LIVE_KID1_ACCOUNT" exit-modal/shell.qml 15 || return 1
  capture exit-modal "$theme"
}

shoot_ask() {
  local theme="$1"
  prepare_kid || return 1
  start_in_session "$LIVE_KID1_ACCOUNT" launcher/shell.qml "/usr/bin/omarchy-kids-ask time 15" || return 1
  wait_vm_process "$LIVE_KID1_ACCOUNT" ask/shell.qml 15 || return 1
  capture ask "$theme"
}

shoot_times_up() {
  local theme="$1" kid_q
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  ORIGINAL_LIGHTS_OUT_SOURCE="$(kid_setting_source lights_out)" || return 1
  if [[ "$ORIGINAL_LIGHTS_OUT_SOURCE" == override ]]; then
    ORIGINAL_LIGHTS_OUT="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf get $kid_q lights_out")" || return 1
  fi
  ORIGINAL_LIGHTS_OUT_WEEKEND_SOURCE="$(kid_setting_source lights_out_weekend)" || return 1
  if [[ "$ORIGINAL_LIGHTS_OUT_WEEKEND_SOURCE" == override ]]; then
    ORIGINAL_LIGHTS_OUT_WEEKEND="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf get $kid_q lights_out_weekend")" || return 1
  fi
  prepare_kid || return 1
  LIGHTS_OUT_DIRTY=1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q lights_out 00:01 >/dev/null" || return 1
  LIGHTS_OUT_WEEKEND_DIRTY=1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q lights_out_weekend 00:01 >/dev/null" || return 1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-time-ledger tick >/dev/null" || return 1
  wait_vm_process "$LIVE_KID1_ACCOUNT" time/timesup.qml 30 || return 1
  capture times-up "$theme"
}

shoot_wifi_picker() {
  local theme="$1" kid_q
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  ORIGINAL_WIFI_SOURCE="$(kid_setting_source wifi)" || return 1
  if [[ "$ORIGINAL_WIFI_SOURCE" == override ]]; then
    ORIGINAL_WIFI="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf get $kid_q wifi")" || return 1
  fi
  prepare_kid || return 1
  WIFI_DIRTY=1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf set $kid_q wifi helper >/dev/null" || return 1
  start_in_session "$LIVE_KID1_ACCOUNT" launcher/shell.qml "/usr/bin/omarchy-kids-wifi picker" || return 1
  wait_vm_process "$LIVE_KID1_ACCOUNT" wifi/shell.qml 15 || return 1
  capture wifi-picker "$theme"
}

shoot_plugins_shelf() {
  local theme="$1" kid_q band band_q command
  kid_q="$(shell_quote "$LIVE_KID1_ACCOUNT")"
  band="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf get $kid_q band")" || return 1
  case "$band" in 3-5 | 6-8 | 9-12 | 13+) ;; *) return 1 ;; esac
  band_q="$(shell_quote "$band")"
  command="OMARCHY_KIDS_BAND=$band_q /usr/bin/quickshell -p /usr/share/omarchy-kids/plugins/shell.qml"
  prepare_kid || return 1
  start_in_session "$LIVE_KID1_ACCOUNT" launcher/shell.qml "$command" || return 1
  wait_vm_process "$LIVE_KID1_ACCOUNT" plugins/shell.qml 15 || return 1
  capture plugins-shelf "$theme"
}

shoot_wizard() {
  local theme="$1"
  prepare_owner || return 1
  start_in_session "$LIVE_OWNER_ACCOUNT" omarchy-shell "/usr/bin/omarchy-launch-floating-terminal-with-presentation /usr/bin/omarchy-kids-wizard --dry-run" || return 1
  wait_vm_process "$LIVE_OWNER_ACCOUNT" omarchy-kids-wizard 15 || return 1
  capture wizard "$theme"
}

shoot_panel() {
  local theme="$1"
  prepare_owner || return 1
  start_in_session "$LIVE_OWNER_ACCOUNT" omarchy-shell "/usr/bin/omarchy-launch-floating-terminal-with-presentation /usr/bin/omarchy-kids-panel --dry-run" || return 1
  wait_vm_process "$LIVE_OWNER_ACCOUNT" omarchy-kids-panel 15 || return 1
  capture panel "$theme"
}

shoot_bar_module() {
  local theme="$1"
  [[ "$(vm "/usr/bin/omarchy-kids-bar status" 2>/dev/null)" == enabled ]] || {
    echo "media-driver: bar module is not enabled; refusing to change the parent's bar" >&2
    return 1
  }
  prepare_kid || return 1
  if vmroot "env -i PATH=/usr/bin:/bin /usr/bin/systemctl is-active --quiet omarchy-kids-time.timer"; then
    TIME_TIMER_STOPPED=1
    vmroot "env -i PATH=/usr/bin:/bin /usr/bin/systemctl stop omarchy-kids-time.timer" || return 1
  fi
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-time-ledger tick >/dev/null" || return 1
  portal_clean_exit "$LIVE_KID1_ACCOUNT" || return 1
  assert_greeter 45 || return 1
  portal_login "$LIVE_OWNER_ACCOUNT" "$LIVE_OWNER_PASSWORD" || return 1
  wait_vm_process "$LIVE_OWNER_ACCOUNT" omarchy-shell 60 || return 1
  vmroot "env -i PATH=/usr/bin:/bin /usr/bin/jq -e '.kids[]? | select(.live == true)' /run/omarchy-kids/status.json >/dev/null" || return 1
  capture bar-module "$theme"
}

run_surface() {
  local surface="$1" theme="$2" function failed=0
  function="shoot_${surface//-/_}"
  echo "Capturing $surface under $theme"
  "$function" "$theme" || failed=1
  restore_transient_state || failed=1
  ((failed)) || return 0
  echo "media-driver: FAILED $surface under $theme" >&2
  return 1
}

boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" || die "owner boot failed"
ORIGINAL_OWNER_THEME="$(vm "export OMARCHY_PATH=/usr/share/omarchy; /usr/bin/omarchy-theme-current")" ||
  die "could not read the owner's current theme"
ORIGINAL_KID_THEME_SOURCE="$(kid_setting_source theme)" ||
  die "could not read $LIVE_KID1_ACCOUNT's theme source"
if [[ "$ORIGINAL_KID_THEME_SOURCE" == override ]]; then
  ORIGINAL_KID_THEME="$(vmroot "env -i PATH=/usr/bin:/bin /usr/bin/omarchy-kids-conf get $(shell_quote "$LIVE_KID1_ACCOUNT") theme")" ||
    die "could not read $LIVE_KID1_ACCOUNT's current theme"
fi
[[ -n "$ORIGINAL_OWNER_THEME" ]] || die "the owner's current theme must be known before capture"
THEMES_SAVED=1

for theme in "${THEMES[@]}"; do
  THEME_DIRTY=1
  if ! apply_owner_theme "$theme" || ! apply_kid_theme "$theme" || ! refresh_portal; then
    echo "media-driver: FAILED to prepare theme '$theme'; skipping its surfaces" >&2
    RUN_FAILED=1
    continue
  fi
  for surface in "${SURFACES[@]}"; do
    [[ -z "$SURFACE_FILTER" || "$surface" == "$SURFACE_FILTER" ]] || continue
    run_surface "$surface" "$theme" || RUN_FAILED=1
  done
done

if ! restore_themes; then RUN_FAILED=1; fi
exit "$RUN_FAILED"
