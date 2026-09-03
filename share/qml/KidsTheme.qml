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
// instantiates this directly (`import "../qml"` then `KidsTheme { id:
// theme }`) rather than using `pragma Singleton`: each shell.qml here is
// already its own separate process, so there is no cross-file singleton
// instance worth sharing within one QML engine — see docs/theming.md.
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
