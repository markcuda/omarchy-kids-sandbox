# Maintainer: Mark Cuda <mc@markcuda.com>
#
# makepkg sources this file itself (setting pkgdir/srcdir/startdir and
# reading pkgname/pkgver/... back out), so the usual "unused"/"not
# assigned" shellcheck warnings for those don't apply here.
# shellcheck shell=bash disable=SC2034,SC2154
#
# This PKGBUILD lives in the repo root and builds from the local checkout,
# not a downloaded tarball: source=() is intentionally empty, so package()
# reads straight from $startdir (the checkout root) instead of $srcdir.
# Build on the test laptop (never as root, never with sudo makepkg):
#   makepkg -sf
# See docs/packaging.md for what gets installed where and how to remove it.

pkgname=omarchy-kids
pkgver=0.1.0
pkgrel=1
pkgdesc="Kids Mode for Omarchy: a Kids Mode app on a normal Omarchy install (sandbox path)"
arch=('x86_64')
url="https://github.com/markcuda/omarchy-kids-sandbox"
license=('MIT')
# qt6-svg (issue #39): the portal's avatars (share/avatars/*.svg) only
# rasterize in the SDDM greeter if Qt's SVG image plugin is loaded.
# UNVERIFIED whether sddm/qt6-declarative already pull this in
# transitively on a real Omarchy 4.0.2 box -- there is no pacman on this
# dev machine to confirm with `pacman -Si sddm`'s own dependency tree,
# and docs/portal.md's "Verified live" run predates this fix. Listed
# explicitly rather than assumed, since an extra depends= on an already-
# satisfied package is a no-op, but a missing one silently ships the
# letter-circle fallback forever.
depends=('bash' 'gum' 'jq' 'python' 'cryptsetup' 'polkit' 'sudo' 'systemd' 'qt6-svg')
optdepends=('socat: faster transport between omarchy-kids-parent-auth and omarchy-kids-authd')
install=omarchy-kids.install
source=()
backup=('etc/mkinitcpio.conf.d/omarchy_kids.conf')

package() {
	cd "$startdir" || exit 1

	# Commands (R-BUILD-4): every bin/omarchy-kids-* file, whatever exists
	# today plus whatever lands later -- this glob needs no updating.
	install -dm755 "$pkgdir/usr/bin"
	install -m755 bin/omarchy-kids bin/omarchy-kids-* "$pkgdir/usr/bin/"

	# Early-boot LUKS-unlock hook (R-BOOT).
	install -dm755 "$pkgdir/usr/lib/omarchy-kids"
	install -m644 lib/*.sh lib/*.py "$pkgdir/usr/lib/omarchy-kids/"
	install -dm755 "$pkgdir/usr/lib/initcpio/hooks" "$pkgdir/usr/lib/initcpio/install"
	install -m755 initcpio/hooks/* "$pkgdir/usr/lib/initcpio/hooks/"
	install -m755 initcpio/install/* "$pkgdir/usr/lib/initcpio/install/"
	install -Dm755 initcpio/omarchy-kids-open "$pkgdir/usr/lib/initcpio/omarchy-kids-open"

	# HOOKS insertion (R-BOOT-2). Marked backup= above: it's a config file
	# under /etc that a local admin could reasonably hand-edit.
	install -Dm644 etc/mkinitcpio.conf.d/omarchy_kids.conf \
		"$pkgdir/etc/mkinitcpio.conf.d/omarchy_kids.conf"

	# systemd units (authd socket/service, boot-login + its cleanup unit,
	# the screen-time ledger's timer/service, R-TIME-1, and the ask-collect timer,
	# R-ASK-1..3, issue #25).
	install -dm755 "$pkgdir/usr/lib/systemd/system"
	install -m644 systemd/*.service systemd/*.socket systemd/*.timer "$pkgdir/usr/lib/systemd/system/"

	# Data: bands, packs, hyprland, tui, policy, avatars, menu, sddm-theme.
	# cp -a preserves the share/ subtree; .gitkeep placeholders are pruned
	# afterward so empty data dirs still exist without shipping git litter.
	install -dm755 "$pkgdir/usr/share/omarchy-kids"
	cp -a share/. "$pkgdir/usr/share/omarchy-kids/"
	find "$pkgdir/usr/share/omarchy-kids" -name '.gitkeep' -delete

	# The portal (R-LOGIN, issue #14): SDDM only looks for greeter themes
	# under /usr/share/sddm/themes/<name>/, not under our own share dir --
	# so share/sddm-theme/ is installed there too, selected at runtime by
	# lib/posture.sh's posture_write_sddm_theme_dropin
	# (/etc/sddm.conf.d/zz-omarchy-kids-theme.conf).
	install -dm755 "$pkgdir/usr/share/sddm/themes/omarchy-kids"
	cp -a share/sddm-theme/. "$pkgdir/usr/share/sddm/themes/omarchy-kids/"
	find "$pkgdir/usr/share/sddm/themes/omarchy-kids" -name '.gitkeep' -delete

	# pacman hook: re-assert every lock after any transaction (R-TRUST-5).
	install -Dm644 pacman/omarchy-kids.hook \
		"$pkgdir/usr/share/libalpm/hooks/omarchy-kids.hook"

	# Desktop entries: the app, and the kid Wayland session.
	install -Dm644 desktop/omarchy-kids.desktop \
		"$pkgdir/usr/share/applications/omarchy-kids.desktop"
	install -Dm644 desktop/omarchy-kids-session.desktop \
		"$pkgdir/usr/share/wayland-sessions/omarchy-kids.desktop"

	# License.
	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
