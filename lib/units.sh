# shellcheck shell=bash
# shellcheck disable=SC2034 # KIDS_UNITS/KIDS_SOCKETS/KIDS_TIMERS are read by sourcing callers, not here
# lib/units.sh -- the package's own systemd units (R-BOOT-3, R-SEC-2), one
# list shared by omarchy-kids-assert's "units" lock and the wizard's Apply.

KIDS_UNITS=(omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service)
# wifid.socket: without it, a helper-mode kid's wifi command fails closed
# with "no reply" (docs/wifi.md) rather than silently doing nothing.
KIDS_SOCKETS=(omarchy-kids-authd.socket omarchy-kids-wifid.socket)
# ask-collect.timer: the every-minute backstop that applies an "ask a
# parent" request submitted while no one was running the panel.
KIDS_TIMERS=(omarchy-kids-time.timer omarchy-kids-ask-collect.timer)
