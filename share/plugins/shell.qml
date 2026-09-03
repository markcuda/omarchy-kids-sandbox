// shell.qml -- the kids-plugins shelf overlay (SPEC.md R-APPS-7; I-5
// keyboard-complete, I-6 honest UI; issue #28). Loaded standalone with
// `quickshell -p share/plugins/shell.qml`, exec'd directly from the
// Level 1 launcher's own "More apps" tile
// (bin/omarchy-kids-session-start, bands 6-8 and up only -- 3-5 gets no
// tile at all). Unlike share/ask/shell.qml this needs no password step
// and no dedicated omarchy-kids-* wrapper to exec it: the tile's own
// exec line already sets OMARCHY_KIDS_BAND, and that's the only input
// this file needs before it can show something.
//
// Read-only (SPEC.md's own words for this issue): this file never
// installs, never writes anything, never talks to root. Enter on an
// item runs `omarchy-kids-ask app <plugin>` -- the existing "Ask a
// grown-up" flow (share/ask/shell.qml) -- and this overlay quits right
// after, handing off to that modal rather than layering two overlays.
//
// Reuses, line for line, the layer-shell/keyboard-focus shape
// share/exit-modal/shell.qml verified live against a real
// Hyprland+Quickshell session (docs/exit.md's "Verified live" section,
// 2026-09-02; share/ask/shell.qml's header repeats the same citation):
//   - PanelWindow + WlrLayershell.layer: WlrLayer.Overlay, and
//     WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive.
//   - Any action runs via Quickshell.execDetached, never a child
//     Process, and only *after* that call does this quit.
//
// ============================== UNTESTED ================================
// Specifically for *this* file, beyond the layer-shell shape above:
//   - `Quickshell.Io.Process`'s `stdout: StdioCollector { onStreamFinished }`
//     shape for capturing a finished command's whole stdout. Nothing
//     else in this repo captures a Process's output (share/ask and
//     share/launcher only ever start a Process and read its exit code,
//     or write to its stdin) -- this is a best-effort guess at the real
//     Quickshell.Io API, not confirmed against Quickshell docs or
//     source (none were available while writing this). If
//     `StdioCollector`/`onStreamFinished`/`.text` aren't the real names,
//     this is the piece to redo.
//   - Everything share/launcher/shell.qml's own UNTESTED banner already
//     flags (Window vs PanelWindow choice aside, since this file uses
//     PanelWindow directly): FileView-free here, so that part doesn't
//     apply, but the general "never run against a real Quickshell"
//     caveat does. Confirm in the VM per docs/plugins.md before
//     trusting this in front of a kid.
// ==========================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: true

    // --- Inputs (bin/omarchy-kids-session-start sets OMARCHY_KIDS_BAND
    //     on the tile's own exec line) -----------------------------------
    property string band: Quickshell.env("OMARCHY_KIDS_BAND") || ""
    property string pluginsBin: Quickshell.env("OMARCHY_KIDS_PLUGINS_BIN") || "omarchy-kids-plugins"
    property string askBin: Quickshell.env("OMARCHY_KIDS_ASK_BIN") || "omarchy-kids-ask"

    // --- Shelf data: `omarchy-kids-plugins shelf --json [--band ...]`,
    //     the same verified-Kids-only filter the panel's own screen
    //     uses -- this overlay never passes --all (I-6: nothing a kid
    //     can Enter on should be anything but installable). -----------
    property var shelf: []
    property int currentIndex: 0
    property bool loaded: false
    property string loadError: ""

    Process {
        id: shelfProcess
        command: root.band.length > 0
            ? [root.pluginsBin, "shelf", "--json", "--band", root.band]
            : [root.pluginsBin, "shelf", "--json"]
        stdout: StdioCollector {
            id: shelfStdout
            onStreamFinished: root.handleShelf(shelfStdout.text)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0 && !root.loaded) {
                root.loaded = true
                root.loadError = "Could not load the shelf."
            }
        }
    }

    Component.onCompleted: shelfProcess.running = true

    function handleShelf(text) {
        root.loaded = true
        var parsed = []
        try {
            var data = JSON.parse(text)
            if (Array.isArray(data)) parsed = data
        } catch (e) {
            parsed = []
            root.loadError = "Could not read the shelf."
        }
        root.shelf = parsed
        if (root.currentIndex >= root.shelf.length) {
            root.currentIndex = Math.max(0, root.shelf.length - 1)
        }
    }

    // --- Enter: hand off to the existing Ask flow, then close -----------
    function askForCurrent() {
        if (root.currentIndex < 0 || root.currentIndex >= root.shelf.length) return
        var item = root.shelf[root.currentIndex]
        if (!item || !item.id) return
        Quickshell.execDetached([root.askBin, "app", item.id])
        Qt.quit()
    }

    function moveUp() {
        if (root.currentIndex > 0) root.currentIndex -= 1
    }
    function moveDown() {
        if (root.currentIndex < root.shelf.length - 1) root.currentIndex += 1
    }
    function closeModal() {
        Qt.quit() // Esc: read-only, nothing to undo -- just leave.
    }

    // --- The card ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#99000000"

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 560
            height: Math.min(parent.height - 96, 640)
            radius: 24
            color: "#1c1f2b"
            border.color: "#3a4266"
            border.width: 2

            FocusScope {
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: (event) => { root.closeModal(); event.accepted = true }
                Keys.onUpPressed: (event) => { root.moveUp(); event.accepted = true }
                Keys.onDownPressed: (event) => { root.moveDown(); event.accepted = true }
                Keys.onReturnPressed: (event) => { root.askForCurrent(); event.accepted = true }
                Keys.onEnterPressed: (event) => { root.askForCurrent(); event.accepted = true }

                Column {
                    anchors.fill: parent
                    anchors.margins: 32
                    spacing: 16

                    Text {
                        width: parent.width
                        text: "More apps"
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: "Pick one, then press Enter to ask a grown-up."
                        color: "#c8ccdc"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    // --- Loading / empty / error states (I-6: never a
                    //     blank screen with no explanation) --------------
                    Text {
                        width: parent.width
                        visible: !root.loaded
                        text: "Looking for apps to add…"
                        color: "#c8ccdc"
                        font.pixelSize: 15
                    }

                    Text {
                        width: parent.width
                        visible: root.loaded && root.loadError.length > 0
                        text: root.loadError
                        color: "#ffb0b0"
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.loaded && root.loadError.length === 0 && root.shelf.length === 0
                        text: "Nothing here yet -- check back later!"
                        color: "#c8ccdc"
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                    }

                    // --- The list --------------------------------------
                    ListView {
                        id: shelfList
                        width: parent.width
                        height: parent.height - 140
                        visible: root.loaded && root.shelf.length > 0
                        model: root.shelf
                        currentIndex: root.currentIndex
                        clip: true
                        spacing: 8
                        interactive: false

                        delegate: Rectangle {
                            width: shelfList.width
                            height: 76
                            radius: 12
                            color: ListView.isCurrentItem ? "#3a4266" : "#232838"
                            border.width: ListView.isCurrentItem ? 3 : 0
                            border.color: "#8fb8ff"

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 16
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: (modelData.name || modelData.id || "")
                                        + (modelData.age ? "  ·  ages " + modelData.age + "+" : "")
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.description || ""
                                    color: "#c8ccdc"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
