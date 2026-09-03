// shell.qml — the Level 1/2 big-tile launcher (SPEC.md R-DESK-3,
// R-DESK-5, Appendix E; I-5 keyboard-complete, I-6 honest UI).
//
// ============================== UNTESTED ================================
// This file has never run against a real Quickshell or Hyprland session --
// there is no Quickshell install, headless or otherwise, on the machine
// this was written on, and no Quickshell documentation or source was
// available to check API names against. Every Quickshell-specific type
// and property below (as opposed to plain QtQuick ones) is a best-effort
// guess from general knowledge of the project and MUST be checked against
// the real thing in the VM before this ships. In particular:
//
//   - `Window` vs `PanelWindow`/`WlrLayershell`. The issue that asked for
//     this file suggested a layer-shell panel. This file uses a plain
//     QtQuick `Window` instead, fullscreened like every other Level 1/2
//     app via share/hyprland/L1.lua's `o.window(".*", { fullscreen = true })`
//     windowrule, and reachable by title with plain `hyprctl dispatch
//     focuswindow` (see bin/omarchy-kids-launcher-ctl). That sidesteps
//     needing Quickshell's IPC system (whose CLI syntax could not be
//     confirmed at all) just to show/raise the launcher, at the cost of
//     not being a "real" always-on-top overlay. If Quickshell requires
//     PanelWindow for anything it loads, or if a real always-on-top
//     overlay is wanted after all, this is the piece to redo.
//   - `Quickshell.Io.FileView` — whether `reload()`/`text()` exist with
//     those names and signatures, and how a missing file is reported
//     (this assumes `text()` throws or returns empty rather than crashing
//     the shell).
//   - `Quickshell.Io.Process` — whether `command`/`running` are real
//     properties and start-on-`running=true` is the right lifecycle.
//   - issue #43: `columns` below assumes GridView lays tiles out at
//     exactly `Math.floor(grid.width / grid.cellWidth)` per row (plain
//     QtQuick GridView behavior in general, but not confirmed against
//     this Quickshell 0.3.1 build specifically). If the real layout
//     rounds or reserves space differently, `GridNav.columnsFor()` in
//     gridnav.js is the one place to correct -- key navigation and the
//     GridView both read that same value, so a fix there fixes both.
//   - issue #54: `Quickshell.iconPath()` (used by `iconSource()` below)
//     is confirmed to exist and to be the real Omarchy launcher's own
//     icon lookup -- `shell/services/AppLibrary.qml`'s `iconSource()`
//     (omacom/omarchy@v4.0.2, commit
//     346e69e1cec6c4e8924531874af6ba010a1bc99e) calls
//     `Quickshell.iconPath(value, true)` the same way -- but the exact
//     rendered size/DPI behavior of the returned source still needs a
//     real Quickshell to confirm, like everything else in this file.
//
// What this does NOT depend on the kid's home for (I-3): the tile list
// comes from $XDG_RUNTIME_DIR/omarchy-kids/launcher-<uid>.json (written by session-start),
// and the control file is under /run too. Nothing here reads ~/.config.
// ==========================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import "gridnav.js" as GridNav

Window {
    id: root

    // Theme colors/font (docs/theming.md) — every literal hex below has
    // been replaced by a `theme.*` reference; see share/qml/KidsTheme.qml
    // for where these come from and why this file can't `import
    // qs.Commons` directly.
    KidsTheme { id: theme }

    // A stable, plain-QtQuick-`Window.title` is what
    // bin/omarchy-kids-launcher-ctl matches on with `hyprctl dispatch
    // focuswindow title:^(...)$` — keep this string in sync with that
    // script if it ever changes.
    title: "Omarchy Kids Launcher"
    visible: true
    visibility: Window.FullScreen
    color: theme.background

    // --- Tile data -----------------------------------------------------
    // Written by bin/omarchy-kids-session-start from the kid's resolved
    // allowlist. Read once at startup and again whenever the file
    // changes underneath (a level change, a re-run of session-start).
    property var tiles: []
    // issue #43: this used to be a hardcoded `4` that drifted out of
    // sync with what GridView actually renders (five columns, seen live
    // with ten tiles). Derived here from the exact same inputs --
    // grid.width and grid.cellWidth -- GridView itself uses to lay tiles
    // out, via the shared pure function in gridnav.js, so key navigation
    // and the rendered layout can never disagree on column count again.
    readonly property int columns: GridNav.columnsFor(grid.width, grid.cellWidth)
    property int currentIndex: 0

    // --- Grid layout (issue #54) -----------------------------------------
    // Live at 1280x800: two tiles sat top-left with the rest of the
    // screen empty, and ten tiles filled only the top third -- GridView
    // was anchored top-left, full-width, with a hardcoded 160px cell.
    // margin is one number so the grid's left/right/top edges and the
    // clock's top-right position (below) share the exact same inset.
    // targetColumns/minTileWidth is the "five per row at 1280, tile
    // width derived, min 160px" rule from the issue: cellSize is
    // whatever width fits five tiles in the space left after margin on
    // each side, floored at minTileWidth, so a bigger screen gets bigger
    // tiles (not just more of them) and a narrower one falls back to
    // fewer than five per row -- grid.width below (columns actually
    // rendered * cellSize) drives GridNav.columnsFor() the same way it
    // always has, so this never disagrees with itself.
    readonly property int margin: 56
    readonly property int minTileWidth: 160
    readonly property int targetColumns: 5
    readonly property real availableWidth: Math.max(minTileWidth, root.width - margin * 2)
    readonly property int cellSize: Math.max(minTileWidth, Math.floor(availableWidth / targetColumns))
    // How many columns the grid itself should be exactly as wide as --
    // never more than targetColumns, and never more than there are
    // tiles to show (so two tiles sit in a small, centred 2-wide grid
    // instead of a full-width one with empty space to their right, the
    // live "two tiles top-left, the rest empty" screenshot this issue
    // is fixing).
    readonly property int neededColumns: Math.max(1, Math.min(targetColumns, tiles.length))

    // iconSource ICON -> a themed icon file/URL for a freedesktop
    // Icon= value, or "" if nothing resolves. Same shape as the real
    // Omarchy shell's own launcher icon lookup --
    // shell/services/AppLibrary.qml's iconSource() (omacom/omarchy
    // @v4.0.2, commit 346e69e1cec6c4e8924531874af6ba010a1bc99e): an
    // already-literal file://, image://, or absolute-path source is
    // used as-is; otherwise Quickshell.iconPath(name, true) resolves the
    // name through the active icon theme, the same call that file makes.
    // Unlike that file, an unresolved name here returns "" rather than
    // falling back to a generic "application-x-executable" glyph -- the
    // delegate below draws a rounded initial instead (I-6: no icon
    // resolving isn't hidden behind a placeholder that looks like one).
    function iconSource(icon) {
        var value = String(icon || "")
        if (value.length === 0) return ""
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
        if (value.charAt(0) === "/") return "file://" + value
        return Quickshell.iconPath(value, true)
    }

    FileView {
        id: tilesFile
        path: (Quickshell.env("OMARCHY_KIDS_LAUNCHER_JSON") || (Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-kids/launcher.json"))
        watchChanges: true
        onLoaded: root.reloadTiles()
        onTextChanged: root.reloadTiles()
    }

    function reloadTiles() {
        var parsed = []
        try {
            var data = JSON.parse(tilesFile.text())
            if (data && data.tiles) parsed = data.tiles
        } catch (e) {
            parsed = []
        }
        root.tiles = parsed
        if (root.currentIndex >= root.tiles.length) {
            root.currentIndex = Math.max(0, root.tiles.length - 1)
        }
    }

    Component.onCompleted: root.reloadTiles()

    // --- Reaching this window from Hyprland binds -----------------------
    // Super+Home and Super+Space (share/hyprland/L1.lua, L2.lua) focus
    // this window directly via `hyprctl dispatch focuswindow`, which
    // needs no cooperation from this file. Super+Enter ("open selected")
    // is different: it has to reach *this app's* idea of which tile is
    // highlighted, which a window-focus dispatch alone can't do. Rather
    // than guess Quickshell's IPC call syntax, bin/omarchy-kids-launcher-ctl
    // writes a one-line command into a control file this polls. Polling
    // (not a file-watch signal) is deliberate: it's the one mechanism
    // here with no Quickshell-specific behavior to get wrong.
    property string lastControlText: ""

    FileView {
        id: controlFile
        path: (Quickshell.env("OMARCHY_KIDS_LAUNCHER_CONTROL") || (Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-kids/launcher-control"))
    }

    Timer {
        interval: 150
        running: true
        repeat: true
        onTriggered: {
            controlFile.reload()
            var text = (controlFile.text() || "").trim()
            if (text.length > 0 && text !== root.lastControlText) {
                root.lastControlText = text
                // First word is the command; omarchy-kids-launcher-ctl
                // appends a nonce so the same command can fire twice in
                // a row without this file having to truncate the
                // control file back to empty itself.
                var command = text.split(/\s+/)[0]
                if (command === "activate") root.launchCurrent()
            }
        }
    }

    // --- Launching a tile -------------------------------------------------
    Process {
        id: launcherProcess
        onExited: running = false
    }

    // R-DATA-1 (issue #27): fire-and-forget record of "a tile was
    // opened", one line per launch, via the kid-writable half of the
    // launch log (bin/omarchy-kids-launcher-ctl's own header explains
    // why this can't just write the root-owned log directly -- I-3).
    // Never allowed to affect the real launch above/below: a failure
    // here is invisible to the kid either way, same as launcherProcess
    // itself never surfaces an error.
    Process {
        id: logProcess
        onExited: running = false
    }

    function launchCurrent() {
        if (root.currentIndex < 0 || root.currentIndex >= root.tiles.length) return
        var tile = root.tiles[root.currentIndex]
        if (!tile || !tile.exec) return
        // issue #42, I-6: a tile bin/omarchy-kids-session-start kept
        // only because apps.show_missing=yes (installed === false,
        // explicitly, not just falsy/undefined -- every other tile
        // this launcher has ever rendered has no `installed` key at
        // all and must keep working) is shown greyed with a caption
        // below, never launched -- Enter on it is a no-op, same as
        // Escape everywhere else in this file.
        if (tile.installed === false) return
        logProcess.command = ["/usr/bin/omarchy-kids-launcher-ctl", "log", tile.id || ""]
        logProcess.running = true
        launcherProcess.command = ["sh", "-c", tile.exec]
        launcherProcess.running = true
    }

    // --- Keyboard navigation (I-5: keyboard-complete) --------------------
    // Plain arrows/Return/Escape, handled entirely inside this app while
    // it has focus -- no Hyprland bind needed for these (Appendix E does
    // not list plain arrow keys for Level 1; Super+arrows at Level 2 is a
    // separate, window-focus feature in share/hyprland/L2.lua).
    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        // issue #43: index math lives in gridnav.js, not here, so it's
        // one shared implementation instead of four inline expressions
        // that can each drift from the layout (and from each other)
        // independently. Left/Right wrap to the previous/next row --
        // clamping only at the very first/last tile -- since tiles are
        // laid out row-major and index+/-1 already crosses a row
        // boundary correctly on its own; see gridnav.js's header for
        // why that's the design, not a shortcut. Up/Down clamp at the
        // top/bottom edge (including a ragged last row) rather than
        // jumping to some other tile.
        Keys.onLeftPressed: (event) => {
            root.currentIndex = GridNav.moveLeft(root.currentIndex)
            event.accepted = true
        }
        Keys.onRightPressed: (event) => {
            root.currentIndex = GridNav.moveRight(root.currentIndex, root.tiles.length)
            event.accepted = true
        }
        Keys.onUpPressed: (event) => {
            root.currentIndex = GridNav.moveUp(root.currentIndex, root.columns)
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            root.currentIndex = GridNav.moveDown(root.currentIndex, root.columns, root.tiles.length)
            event.accepted = true
        }
        Keys.onReturnPressed: (event) => { root.launchCurrent(); event.accepted = true }
        Keys.onEnterPressed: (event) => { root.launchCurrent(); event.accepted = true }
        // "Escape does nothing": explicitly swallowed so it can never
        // close or hide the launcher -- there is no other screen behind
        // it to fall back to (I-6: don't offer an exit this isn't).
        Keys.onEscapePressed: (event) => { event.accepted = true }

        // issue #54: centred in the upper part of the screen, not
        // anchors.fill -- width is exactly as many cells as fit (never
        // the full window width, so it centres instead of hugging the
        // left edge with two tiles), and height is exactly as many rows
        // as the tile count needs (never the full window height, so
        // this sits in the upper third with the rest of the screen
        // empty below it, matching the issue's live screenshots).
        //
        // Live at 1280x800 with nine tiles: the clock (top-right, same
        // root.margin top inset as the grid) overlapped the fifth tile
        // of the first row -- both sat in the same horizontal band, and
        // a centred five-wide grid reaches close enough to the right
        // edge to pass under it. Fixed by giving the clock its own band
        // above the grid instead: grid top = clock bottom + margin
        // (clockText's own top inset, root.margin, plus its height,
        // plus one more root.margin gap before the grid starts) --
        // never just root.margin on its own, so there is no width past
        // which the two can touch, regardless of tile count.
        GridView {
            id: grid
            anchors.top: parent.top
            anchors.topMargin: root.margin + clockText.height + root.margin
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.availableWidth, cellWidth * root.neededColumns)
            height: Math.max(cellHeight, Math.ceil(root.tiles.length / Math.max(1, root.columns)) * cellHeight)
            cellWidth: root.cellSize
            cellHeight: root.cellSize
            model: root.tiles
            currentIndex: root.currentIndex
            interactive: false

            delegate: Rectangle {
                // issue #42, I-6: a tile whose app isn't installed yet
                // (bin/omarchy-kids-session-start only ever emits one
                // when apps.show_missing=yes; otherwise it's omitted
                // entirely and never reaches this file) is greyed and
                // captioned instead of looking like every other tile --
                // it can be highlighted for consistent arrow-key
                // navigation, but launchCurrent() above refuses to run
                // it. `=== false`, not falsy: every other tile here
                // carries no `installed` key at all and must render
                // exactly as before.
                readonly property bool missing: modelData.installed === false
                // issue #54: the resolved icon source, or "" -- an
                // empty Image source (Image.Null) never reaches
                // Image.Ready, so the rounded-initial fallback below
                // shows automatically with no extra branching here.
                readonly property string resolvedIcon: root.iconSource(modelData.icon)
                readonly property string initial: {
                    var s = String(modelData.label || modelData.id || "?").trim()
                    return s.length > 0 ? s.charAt(0).toUpperCase() : "?"
                }

                // issue #54: derived from the shared cell size (min
                // 160px per the issue), inset from the cell itself so
                // adjacent tiles never touch -- still comfortably over
                // the 96px tap-target floor even at the smallest cell.
                width: grid.cellWidth - 20
                height: grid.cellHeight - 20
                radius: 16
                color: missing ? theme.background : (GridView.isCurrentItem ? theme.tileFill : theme.cardFill)
                opacity: missing ? 0.55 : 1.0
                // Highlight ring in the theme accent (docs/theming.md) --
                // only the current tile gets a border at all.
                border.width: GridView.isCurrentItem ? 4 : 0
                border.color: theme.accent

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Item {
                        id: iconSlot
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64

                        Image {
                            id: iconImg
                            anchors.fill: parent
                            source: resolvedIcon
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }

                        // issue #54: no icon resolved through
                        // Quickshell.iconPath() (a fresh install not yet
                        // in the icon theme cache, a bad Icon= name, or
                        // no Icon= at all) -- a rounded initial in the
                        // theme accent colour instead of a broken-image
                        // glyph or empty space, so every tile still
                        // looks intentional (I-6).
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: theme.accent
                            visible: !iconImg.visible

                            Text {
                                anchors.centerIn: parent
                                text: initial
                                color: theme.background
                                font.family: theme.fontFamily
                                // Live review: bumped from 28 to 32 so the
                                // initial reads at roughly the same visual
                                // weight as a real 64px icon glyph in the
                                // same iconSlot, not visibly smaller.
                                font.pixelSize: 32
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label || modelData.id || ""
                        color: theme.foreground
                        font.family: theme.fontFamily
                        font.pixelSize: 18
                        wrapMode: Text.WordWrap
                        width: parent.parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // "installing..." while omarchy-kids-apps' queue for
                    // this app is pending, else "not installed yet" --
                    // set by bin/omarchy-kids-session-start, never
                    // computed here (this file has no way to read the
                    // queue itself, and shouldn't need one).
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: missing && modelData.caption && modelData.caption.length > 0
                        text: modelData.caption || ""
                        color: theme.muted
                        font.family: theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        width: parent.parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // --- Clock ---------------------------------------------------------
    // issue #54 (live review fix): id: clockText so the grid above can
    // bind its own top margin to clockText.height -- the clock gets its
    // own band above the grid (grid top = clock bottom + margin)
    // instead of sharing the grid's top inset, which overlapped the
    // fifth tile of row one in the live 1280x800/nine-tile screenshot.
    Text {
        id: clockText
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.margin
        anchors.rightMargin: root.margin
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: 28
        text: Qt.formatTime(new Date(), "hh:mm")

        Timer {
            interval: 15000
            running: true
            repeat: true
            onTriggered: parent.text = Qt.formatTime(new Date(), "hh:mm")
        }
    }
}
