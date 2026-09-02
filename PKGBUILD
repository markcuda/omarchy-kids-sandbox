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
depends=('bash' 'gum' 'jq' 'python' 'cryptsetup' 'polkit' 'sudo' 'systemd')
optdepends=('socat: faster transport between omarchy-kids-parent-auth and omarchy-kids-authd')
install=omarchy-kids.install
source=()
backup=('etc/mkinitcpio.conf.d/omarchy_kids.conf')

package() {
	cd "$startdir" || exit 1

	# Commands (R-BUILD-4): every bin/omarchy-kids-* file, whatever exists
	# today plus whatever lands later -- this glob needs no updating.
	install -dm755 "$pkgdir/usr/bin"
	install -m755 bin/omarchy-kids-* "$pkgdir/usr/bin/"

	# Early-boot LUKS-unlock hook (R-BOOT).
	install -dm755 "$pkgdir/usr/lib/initcpio/hooks" "$pkgdir/usr/lib/initcpio/install"
	install -m755 initcpio/hooks/* "$pkgdir/usr/lib/initcpio/hooks/"
	install -m755 initcpio/install/* "$pkgdir/usr/lib/initcpio/install/"
	install -Dm755 initcpio/omarchy-kids-open "$pkgdir/usr/lib/initcpio/omarchy-kids-open"

	# HOOKS insertion (R-BOOT-2). Marked backup= above: it's a config file
	# under /etc that a local admin could reasonably hand-edit.
	install -Dm644 etc/mkinitcpio.conf.d/omarchy_kids.conf \
		"$pkgdir/etc/mkinitcpio.conf.d/omarchy_kids.conf"

	# systemd units (authd socket/service, boot-login + its cleanup unit).
	install -dm755 "$pkgdir/usr/lib/systemd/system"
	install -m644 systemd/*.service systemd/*.socket "$pkgdir/usr/lib/systemd/system/"

	# Data: bands, packs, hyprland, tui, policy, avatars, menu, sddm-theme.
	# cp -a preserves the share/ subtree; .gitkeep placeholders are pruned
	# afterward so empty data dirs still exist without shipping git litter.
	install -dm755 "$pkgdir/usr/share/omarchy-kids"
	cp -a share/. "$pkgdir/usr/share/omarchy-kids/"
	find "$pkgdir/usr/share/omarchy-kids" -name '.gitkeep' -delete

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
