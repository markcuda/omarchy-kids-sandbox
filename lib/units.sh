# shellcheck shell=bash
# shellcheck disable=SC2034 # KIDS_UNITS/KIDS_SOCKETS/KIDS_TIMERS are read by sourcing callers, not here
# lib/units.sh — the package's own systemd units (R-BOOT-3, R-SEC-2), one
# list shared by bin/omarchy-kids-assert (the "units" lock, docs/assert.md)
# and bin/omarchy-kids-wizard (Apply's first step, issue #46). Without
# these enabled and running, the per-boot autologin drop-in is never
# written (R-BOOT-3) and the parent-password socket A2 prefers
# (docs/authd.md) is down — true on a fresh install before the first kid,
# and right after `omarchy-kids-remove` disables them again. Kept here,
# not duplicated, so the two callers can never drift out of sync with
# systemd/*.service, *.socket, *.timer.
#
# Not meant to be executed directly; source it from a command:
#   source "$DIR/lib/units.sh"

KIDS_UNITS=(omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service)
# omarchy-kids-wifid.socket (R-WIFI-2, issue #26): the same treatment as
# authd's socket — without it enabled, a helper-mode kid's
# omarchy-kids-wifi never gets a reply from anything, and every
# subcommand fails closed with "no reply" rather than silently doing
# nothing (see docs/wifi.md).
KIDS_SOCKETS=(omarchy-kids-authd.socket omarchy-kids-wifid.socket)
# omarchy-kids-ask-collect.timer (R-ASK-1..3, issue #25): the every-minute
# backstop that applies an "ask a parent" request a kid submitted while
# no one was running the panel.
KIDS_TIMERS=(omarchy-kids-time.timer omarchy-kids-ask-collect.timer)
