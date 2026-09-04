#!/bin/bash
# Tests the ticket's package migration (R-BOOTMODE-1, R-BOOTMODE-12).
# Static checks only: no makepkg, pacman, or /etc writes run here.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { echo "ok   $*"; }
bad() {
	echo "FAIL $*"
	fail=1
}

if [[ -f "$ROOT/share/boot/omarchy_kids.conf" ]]; then
	ok "boot template is shipped under share/boot"
else
	bad "boot template is missing from share/boot"
fi

if [[ ! -e "$ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" ]]; then
	ok "active mkinitcpio drop-in is not in the source package"
else
	bad "source package still contains the active mkinitcpio drop-in"
fi

if grep -qF 'etc/mkinitcpio.conf.d/omarchy_kids.conf' "$ROOT/PKGBUILD"; then
	bad "PKGBUILD still owns the active drop-in"
else
	ok "PKGBUILD no longer owns the active drop-in"
fi

if [[ -f "$ROOT/.SRCINFO" ]] && grep -qF 'backup = etc/mkinitcpio.conf.d/omarchy_kids.conf' "$ROOT/.SRCINFO"; then
	bad ".SRCINFO still owns the active drop-in"
else
	ok ".SRCINFO no longer owns the active drop-in"
fi

if grep -qF 'share/boot/omarchy_kids.conf' "$ROOT/PKGBUILD" ||
	grep -qF 'cp -a share/. ' "$ROOT/PKGBUILD"; then
	ok "package() ships the inactive boot template"
else
	bad "package() does not ship the inactive boot template"
fi

if bash -n "$ROOT/omarchy-kids.install"; then
	ok "bash -n omarchy-kids.install"
else
	bad "omarchy-kids.install is not valid shell"
fi

if grep -qF '/etc/omarchy-kids/machine.conf' "$ROOT/omarchy-kids.install" &&
	grep -qF '/usr/bin/omarchy-kids-conf machine set boot' "$ROOT/omarchy-kids.install" &&
	! grep -q 'OMARCHY_KIDS_' "$ROOT/omarchy-kids.install"; then
	ok "migration uses fixed paths and the trusted setter"
else
	bad "migration does not use the fixed trusted boot path"
fi

echo "packaging-test RESULT: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit "$fail"
