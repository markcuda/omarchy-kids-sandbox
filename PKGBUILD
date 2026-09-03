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
# networkmanager (issue #26, R-WIFI-2): bin/omarchy-kids-wifid shells
# out to `nmcli` with fixed argument shapes; every current Omarchy
# install already runs NetworkManager for its own Wi-Fi picker
# (`omarchy-menu` -> Wi-Fi / `omarchy-launch-wifi`), but this is listed
# explicitly rather than assumed, same reasoning as qt6-svg above.
# quickshell (issue #32, R-BUILD-1): bin/omarchy-kids-exit, -ask, and
# -session-start all `exec quickshell -p ...` with no `command -v` guard
# -- the exit modal, the ask-a-parent modal, and the Level 1 launcher
# itself do not run without it, unlike hyprctl/loginctl elsewhere in
# bin/, which are genuinely optional and guarded. Any current Omarchy
# install already carries it for the stock desktop's own bar/launcher,
# but it is listed explicitly, same reasoning as qt6-svg above.
# hyprland and sddm are hard dependencies, not assumptions: the kid
# session is a Hyprland session (bin/omarchy-kids-session execs
# /usr/bin/Hyprland) and the portal is an SDDM theme (R-LOGIN). Omarchy
# itself is installed by its own installer, not from a repo, so it cannot
# be listed here -- share/hyprland/L*.lua require /usr/share/omarchy/...
# and bin/omarchy-kids-session-start execs /usr/bin/omarchy-launch-shell,
# both of which omarchy-kids-check reports on when they are missing.
depends=('bash' 'gum' 'jq' 'python' 'cryptsetup' 'polkit' 'sudo' 'systemd' 'qt6-svg' 'networkmanager' 'quickshell' 'hyprland' 'sddm')
# snapper / limine-snapper-sync (R-TRUST-1, issue #38): both guarded with
# `command -v` everywhere they're called (bin/omarchy-kids-assert,
# -remove) -- the pre-apply snapshot and the hidden-snapshot-entries lock
# are skipped, not failed, when either is missing, so neither is a hard
# depends. Any stock Omarchy install already has both (Limine + Snapper
# is the default), but a parent who removed one shouldn't be blocked
# from installing Kids Mode over it.
optdepends=(
	'socat: faster transport between omarchy-kids-parent-auth and omarchy-kids-authd'
	'snapper: pre-apply "before Kids Mode" snapshot and Remove Kids Mode snapshot (R-TRUST-1)'
	'limine-snapper-sync: refresh the boot menu right after hiding/showing snapshot entries (issue #38)'
)
install=omarchy-kids.install
source=()
backup=('etc/mkinitcpio.conf.d/omarchy_kids.conf')

package() {
	cd "$startdir" || exit 1

	# Commands (R-BUILD-4): every bin/omarchy-kids-* file, whatever exists
	# today plus whatever lands later -- this glob needs no updating.
	# The tui-demo dev tool lives in scripts/, not bin/, so this glob
	# never sees it (docs/tui.md).
	install -dm755 "$pkgdir/usr/bin"
	install -m755 bin/omarchy-kids bin/omarchy-kids-* "$pkgdir/usr/bin/"

	# Early-boot LUKS-unlock hook (R-BOOT).
	install -dm755 "$pkgdir/usr/lib/omarchy-kids"
	install -m644 lib/*.sh lib/*.py "$pkgdir/usr/lib/omarchy-kids/"

	# The one build-time constant (AGENTS.md, "The trust boundary"): no
	# shipped command reads a program, a library or a socket path from its
	# environment, so the packaged copy has the interpreter's absolute path
	# baked in here rather than resolving "python3" through $PATH.
	sed -i 's|^KIDS_PY=python3$|KIDS_PY=/usr/bin/python3|' \
		"$pkgdir/usr/lib/omarchy-kids/kids.sh"
	grep -q '^KIDS_PY=/usr/bin/python3$' "$pkgdir/usr/lib/omarchy-kids/kids.sh" \
		|| { echo "PKGBUILD: KIDS_PY substitution failed" >&2; return 1; }
	install -dm755 "$pkgdir/usr/lib/initcpio/hooks" "$pkgdir/usr/lib/initcpio/install"
	install -m755 initcpio/hooks/* "$pkgdir/usr/lib/initcpio/hooks/"
	install -m755 initcpio/install/* "$pkgdir/usr/lib/initcpio/install/"
	install -Dm755 initcpio/omarchy-kids-open "$pkgdir/usr/lib/initcpio/omarchy-kids-open"

	# HOOKS insertion (R-BOOT-2). Marked backup= above: it's a config file
	# under /etc that a local admin could reasonably hand-edit.
	install -Dm644 etc/mkinitcpio.conf.d/omarchy_kids.conf \
		"$pkgdir/etc/mkinitcpio.conf.d/omarchy_kids.conf"

	# systemd units (authd socket/service, wifid socket/service (R-WIFI-2,
	# issue #26), boot-login + its cleanup unit, the screen-time ledger's
	# timer/service, R-TIME-1, and the ask-collect timer, R-ASK-1..3,
	# issue #25).
	install -dm755 "$pkgdir/usr/lib/systemd/system"
	install -m644 systemd/*.service systemd/*.socket systemd/*.timer "$pkgdir/usr/lib/systemd/system/"

	# Data: bands, packs, hyprland, tui, policy, avatars, menu, sddm-theme,
	# wifi (share/wifi/shell.qml, the kid-facing picker, R-WIFI-1..2).
	# cp -a preserves the share/ subtree; .gitkeep placeholders are pruned
	# afterward so empty data dirs still exist without shipping git litter.
	install -dm755 "$pkgdir/usr/share/omarchy-kids"
	cp -a share/. "$pkgdir/usr/share/omarchy-kids/"
	# Quickshell only resolves types inside a shell's own directory, so the one theme file is
	# installed next to every standalone surface (seen live: "KidsTheme is not a type").
	for d in "$pkgdir"/usr/share/omarchy-kids/{launcher,exit-modal,ask,time,plugins,wifi}; do
		[ -d "$d" ] && cp share/qml/KidsTheme.qml "$d/"
	done
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
