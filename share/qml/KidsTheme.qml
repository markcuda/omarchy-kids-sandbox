// KidsTheme.qml -- theme colors, font, and derived shades for every standalone Quickshell surface (docs/theming.md).
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Fallback palette, kept in sync by hand with lib/theme.sh's THEME_KIDS_FALLBACK.
    property color background: "#1a1b26"
    property color foreground: "#ffffff"
    property color accent: "#8fb8ff"
    property color muted: "#9aa5ce"
    property color error: "#f7768e"
    property color warning: "#ffd27a"
    property string fontFamily: "JetBrainsMono Nerd Font"

    // --- Derived surface colors: plain bindings, re-evaluated when the theme loads (docs/theming.md, "Derived colours").

    // isLight -- Rec. 709 luminance of the background over 0.5; every shade below branches on it.
    property bool isLight: luminance(background) > 0.5
    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // shade(c, delta) -- move HSL lightness by delta, clamped; hue and saturation untouched.
    function shade(c, delta) {
        var l = Math.max(0, Math.min(1, c.hslLightness + delta))
        return Qt.hsla(c.hslHue, c.hslSaturation, l, c.a)
    }

    // raise(c, light, dark) -- the one direction rule: darken a bit on light, lighten more on dark.
    function raise(c, lightAmount, darkAmount) {
        return root.isLight ? root.shade(c, -lightAmount) : root.shade(c, darkAmount)
    }

    // inputFill -- a text field, one step down from the card (issue #57's live finding on light themes).
    property color inputFill: raise(background, 0.06, 0.12)

    // cardFill -- the one-step-raised surface every card border, tile, button and list item shares.
    property color cardFill: raise(background, 0.04, 0.08)

    // tileFill -- the two-step-raised surface of a selected action or the current grid tile.
    property color tileFill: raise(background, 0.09, 0.18)

    // errorFill -- the locked-out password field; the old per-file formula, kept here so no file needs its own.
    property color errorFill: Qt.darker(error, 4)

    // dim -- the scrim behind every modal card: black at 45% on dark, the background at 55% on light (issue #57).
    property color dim: isLight ? Qt.rgba(background.r, background.g, background.b, 0.55)
                                 : Qt.rgba(0, 0, 0, 0.45)

    // loadColors — one pass over colors.toml's lines, matching plain
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
