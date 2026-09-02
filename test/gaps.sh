#!/bin/bash
# Unprivileged checks for home split, kid hash, bus filter, command stubs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/bin/omarchy-kids-session"
STORE="/var/tmp/omarchy-kids-smoke-$UID"
RT="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-kids-smoke"
DENIED="$ROOT/lib/omarchy-kids-denied"
trap 'rm -rf "$STORE"; rm -f "$HOME/.omarchy-parent-secret"' EXIT
rm -rf "$STORE"
mkdir -p "$STORE" "$RT"
chmod 700 "$STORE"
echo kid-marker >"$STORE/I_AM_KID"
echo parent-secret >"$HOME/.omarchy-parent-secret"

export OMARCHY_KIDS_HOME="$STORE"
export OMARCHY_KIDS_RUNTIME="$RT"
export OMARCHY_KIDS_DENIED="$DENIED"

out="$(timeout 12 "$S" enter -- bash -lc '
test -f "$HOME/I_AM_KID" && echo HAVE_KID
test -f "$HOME/.omarchy-parent-secret" && echo LEAK || echo HIDDEN
echo "FLAG=$OMARCHY_KIDS_SESSION"
command -v nmcli >/dev/null && nmcli -v >/dev/null 2>&1 && echo NMCLI_RAN || echo NMCLI_BLOCKED
command -v omarchy-dns >/dev/null && omarchy-dns DHCP >/dev/null 2>&1 && echo DNS_RAN || echo DNS_BLOCKED
')"
grep -qx HAVE_KID <<<"$out"
grep -qx HIDDEN <<<"$out"
grep -qx 'FLAG=1' <<<"$out"
grep -qx NMCLI_BLOCKED <<<"$out"
grep -qx DNS_BLOCKED <<<"$out"

hash="$(printf kidpass | openssl passwd -6 -stdin)"
salt="$(printf '%s' "$hash" | awk -F'$' '{print $3}')"
got="$(printf kidpass | openssl passwd -6 -salt "$salt" -stdin)"
[[ "$got" == "$hash" ]]
bad="$(printf wrong | openssl passwd -6 -salt "$salt" -stdin)"
[[ "$bad" != "$hash" ]]

echo "gaps: ok"
