// KidsTheme.qml — shared theme colors + font for every standalone
// Quickshell surface in this repo (share/launcher, share/exit-modal,
// share/ask, share/time, share/plugins, share/wifi), each loaded with its
// own `quickshell -p <file>` invocation (see any of those files' own
// UNTESTED header) rather than inside Omarchy's own long-running
// omarchy-shell process. That matters here specifically: none of them can
// `import qs.Commons` for Omarchy's own Color/Style singletons (real,
// fetched from omacom/omarchy at tag v4.0.2 — shell/Commons/Color.qml,
// shell/Commons/Style.qml, shell/Commons/qmldir), because that module
// namespace is only registered inside the shell process itself. A plugin
// *of* that process — share/bar/KidsModule.qml, this repo's one file that
// really does run inside omarchy-shell — imports qs.Commons directly
// instead of this file; see its own header for that citation. Nothing in
// this repo sets QML2_IMPORT_PATH (or otherwise gives a bare
// `quickshell -p` invocation Omarchy's own module search path), so this
// file does for every *other* surface what shell/Commons/Color.qml does
// for the real shell: read $HOME/.local/state/omarchy/current/theme's
// files straight off disk.
//
// Ground truth (omacom/omarchy at tag v4.0.2, fetched 2026-09):
//   - bin/omarchy-theme-set: $HOME/.local/state/omarchy/current/theme is
//     a real directory (not a symlink), rebuilt whole on every theme
//     change — never $HOME/.config/omarchy/current/theme, which doesn't
//     exist on this stack.
//   - shell/Commons/Color.qml's loadColors(): the exact same
//     regex-over-lines parse of colors.toml this file's loadColors()
//     below copies, including the color0/color4/color7/color8 fallback
//     chases for background/accent/foreground/muted. Omarchy's own
//     palette has no dedicated "error"/"warning" key — this file (and
//     lib/theme.sh's theme_color, its bash equivalent, kept in sync by
//     hand) maps those to "red" and "orange" (falling back to "yellow"),
//     the same colors Omarchy's generated app configs use for error/
//     warning states.
//   - shell/Commons/Style.qml's fontFamily/fcMatchProc: the shell's own
//     font is always the fontconfig alias "monospace", resolved with
//     `fc-match -f '%{family[0]}' monospace` — never read from
//     colors.toml. fontProcess below runs the identical command, through
//     the Process/StdioCollector/onStreamFinished shape
//     share/bar/KidsModule.qml already uses live in this repo (its own
//     askProcess) — the one Quickshell.Io.Process pattern confirmed to
//     actually work here, not a fresh guess. UNVERIFIED (like everything
//     else in this repo's standalone Quickshell files): whether a bare
//     `running: true` property initializer on Process actually starts it
//     on component completion, the way it does for a Timer elsewhere in
//     this repo (share/launcher/shell.qml's clock) — confirm in the VM;
//     if it doesn't, trigger it from Component.onCompleted instead.
//
// Every share/**/*.qml file that isn't this one or share/bar/KidsModule.qml
// instantiates this directly (`KidsTheme { id: theme }`, no import — see
// this repo's own PKGBUILD, which copies this file beside every standalone
// surface at install time instead) rather than using `pragma Singleton`:
// each shell.qml here is already its own separate process, so there is no
// cross-file singleton instance worth sharing within one QML engine — see
// docs/theming.md.
//
// Issue #57 (light-theme polish): every surface used to derive its own
// "raised tile"/"sunken input"/"dim scrim" look with a per-file
// `Qt.lighter(theme.background, 1.6)`-style call and a magic-number
// factor (this file's own header used to say so — see docs/theming.md's
// history). That broke under a light Omarchy theme (catppuccin-latte,
// live finding): Qt.lighter()/Qt.darker() move a color's HSV *value* in
// one fixed direction regardless of how light the color already is, so
// lightening an already-light background blows toward white with almost
// no contrast, and Qt.darker(background, 1.3) — fine against a dark
// background — lands a light one on a flat mid-grey that reads as a
// *disabled* control (the exit modal's password field, reported live).
// The five properties below replace every one of those per-file calls:
// each one picks its direction from isLight (darker on a light card,
// lighter on a dark one, never the same direction regardless of theme)
// and moves the background's own HSL lightness by a fixed amount instead
// of scaling its HSV value. share/**/*.qml files use these — never a
// fresh Qt.lighter()/Qt.darker() call with a literal factor of their own
// (test/shell.d/qml-theme-static-test.sh enforces this: only this file
// may call Qt.lighter()/Qt.darker() with a literal number).
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // This repo's own dark palette — kept in sync by hand with
    // lib/theme.sh's THEME_KIDS_FALLBACK (its own header comment has the
    // full reasoning): what every share/**/*.qml file already hardcoded
    // before this file existed, so a session with no theme read yet
    // (colorsFile.onLoadFailed, or a colors.toml missing one of these
    // keys) looks exactly as it always has.
    property color background: "#1a1b26"
    property color foreground: "#ffffff"
    property color accent: "#8fb8ff"
    property color muted: "#9aa5ce"
    property color error: "#f7768e"
    property color warning: "#ffd27a"
    property string fontFamily: "JetBrainsMono Nerd Font"

    // --- Derived surface colors (issue #57) -------------------------------
    // See this file's header for why these exist and the direction rule
    // they all follow. Every one is a plain property binding, so it
    // re-evaluates whenever loadColors() above changes root.background —
    // no explicit Connections/signal needed.

    // isLight — relative luminance (sRGB, linear channel weights — these
    // are flat UI panel colors, not photographic ones, so the cheap
    // version is plenty) of the background, Rec. 709 weights, threshold
    // 0.5. Everything below branches on this rather than hardcoding a
    // direction, so a theme this repo has never seen still picks the
    // readable side.
    property bool isLight: luminance(background) > 0.5
    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // shade(c, delta) — move c's HSL lightness by delta (-1..1), clamped
    // to [0, 1]. Hue and saturation untouched, so a themed color stays
    // recognizably itself, only lighter or darker — unlike Qt.lighter()/
    // Qt.darker(), which scale HSV *value* and so move less (or overflow
    // sooner) the lighter a color already is. hslHue/hslSaturation/
    // hslLightness are plain QColor accessors, not something this file
    // invents.
    function shade(c, delta) {
        var l = Math.max(0, Math.min(1, c.hslLightness + delta))
        return Qt.hsla(c.hslHue, c.hslSaturation, l, c.a)
    }

    // raise(c, lightAmount, darkAmount) — the one direction rule every
    // derived color below follows: darken a bit on a light background,
    // lighten more on a dark one. Dark UIs read a "raised" surface best
    // with more contrast headroom than light ones need — mirrors how
    // much further Qt.lighter(theme.background, 1.6)/(2.4) used to move
    // this repo's own dark palette (see cardFill/tileFill below).
    function raise(c, lightAmount, darkAmount) {
        return root.isLight ? root.shade(c, -lightAmount) : root.shade(c, darkAmount)
    }

    // inputFill — a text field's own fill, one step down from the card:
    // 6% darker on light, 12% lighter on dark. Replaces every
    // share/**/*.qml file's own `Qt.darker(theme.background, 1.3)`, which
    // read as a disabled grey block on catppuccin-latte's light card (the
    // live finding this issue fixes) even though it looked right on
    // tokyo-night.
    property color inputFill: raise(background, 0.06, 0.12)

    // cardFill — the subtle one-step-raised look every card/toast border
    // and every unselected tile, button, or list item already shared:
    // they were always the same `Qt.lighter(theme.background, 1.6)` call,
    // just repeated per file. 8% on dark approximates that call's own
    // effect on this file's tokyo-night-shaped fallback palette (worked
    // out in HSL terms: ~+7.7 lightness points); 4% on light keeps the
    // same subtlety without blowing out a light card.
    property color cardFill: raise(background, 0.04, 0.08)

    // tileFill — the more prominent two-step-raised look for a selected
    // action or the current grid tile (every share/**/*.qml file's own
    // `Qt.lighter(theme.background, 2.4)`; ~+17.6 lightness points on
    // this file's dark fallback, so 18% on dark approximates it — 9% on
    // light keeps the same card:tile ratio).
    property color tileFill: raise(background, 0.09, 0.18)

    // errorFill — the locked-out password field's fill (every exit-modal/
    // ask `Qt.darker(theme.error, 4)`). Not reported broken on light
    // themes (issue #57's live finding was inputFill only), so this stays
    // the exact old formula, just here instead of once per file — the
    // static test's "no literal-factor Qt.lighter()/darker() outside this
    // file" rule needs it to live somewhere.
    property color errorFill: Qt.darker(error, 4)

    // dim — the full-screen scrim every modal draws behind its card
    // (every share/**/*.qml file's own `Qt.rgba(0, 0, 0, 0.6)`). Black at
    // 45% reads as a dim on a dark desktop; the same black at 60% crushed
    // a light desktop nearly to black before the card was even drawn
    // (issue #57's other live finding, the launcher going very dark
    // behind the exit modal under catppuccin-latte). On a light theme,
    // dim the background's own color at 55% instead of pure black, so the
    // scrim reads as "dimmed", not "gone".
    property color dim: isLight ? Qt.rgba(background.r, background.g, background.b, 0.55)
                                 : Qt.rgba(0, 0, 0, 0.45)

    // loadColors — one pass over colors.toml's lines, matching plain
    // `key = "#rrggbb"` (or unquoted `key = #rrggbb`) assignments. Copies
    // shell/Commons/Color.qml's own loadColors() regex and fallback
    // chases (background→color0, accent→color4, foreground→color7,
    // muted→color8→foreground) for the four keys Omarchy defines
    // directly, and extends the same idea for error (red→color1) and
    // warning (orange→yellow→color3) — see this file's header for why
    // those two names don't exist in Omarchy's own palette.
    function loadColors(raw) {
        var lines = String(raw || "").split("\n")
        var vals = {}
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
            if (m) vals[m[1]] = m[2]
        }

        if (vals.background) root.background = vals.background
        else if (vals.color0) root.background = vals.color0

        if (vals.foreground) root.foreground = vals.foreground
        else if (vals.color7) root.foreground = vals.color7

        if (vals.accent) root.accent = vals.accent
        else if (vals.color4) root.accent = vals.color4

        if (vals.muted) root.muted = vals.muted
        else if (vals.color8) root.muted = vals.color8
        else root.muted = root.foreground

        if (vals.red) root.error = vals.red
        else if (vals.color1) root.error = vals.color1

        if (vals.orange) root.warning = vals.orange
        else if (vals.yellow) root.warning = vals.yellow
        else if (vals.color3) root.warning = vals.color3
    }

    // Startup load only, like shell/Commons/Color.qml's own colorsFile —
    // each standalone surface here is a short-lived process (opened,
    // used, quits), not a long-running shell that needs live theme-switch
    // IPC. watchChanges: false and printErrors: false so a machine with
    // no theme set yet (colorsFile never loads) silently keeps the
    // fallback palette above instead of logging noise to every kid-facing
    // window's stderr.
    property FileView colorsFile: FileView {
        path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: false
        printErrors: false
        onLoaded: root.loadColors(text())
    }

    property Process fontProcess: Process {
        running: true
        command: ["fc-match", "-f", "%{family[0]}", "monospace"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var name = String(text || "").trim()
                if (name.length > 0) root.fontFamily = name
            }
        }
    }
}
