// KidsTheme.qml -- shared theme colors, font, and derived surface shades
// (issue #57) for every standalone Quickshell surface, none of which can
// `import qs.Commons` outside Omarchy's own shell process -- docs/theming.md.
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
