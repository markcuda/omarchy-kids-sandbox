// KidsModule.qml — the parent's bar widget (SPEC.md R-BAR-1..3, I-1, I-6).
// One dot per kid currently logged in (name initial, minutes left, paused
// flag), a badge with the count of open "ask a parent" requests, and a
// click/Enter menu with quick actions. Installed only by
// `bin/omarchy-kids-bar enable` (SPEC.md I-1: "Writes into the parent's
// own files happen only when the parent asks") -- see docs/bar.md.
//
// ============================== CONFIRMED / UNVERIFIED ====================
// Unlike the other Quickshell files in this repo (share/launcher/shell.qml,
// share/ask/shell.qml, share/time/*.qml), which are standalone
// `quickshell -p <file>` processes with no real Quickshell install to check
// API names against, this file targets Omarchy 4.0.2's real *shell-plugin*
// architecture, fetched and read directly from omacom/omarchy at tag
// v4.0.2 while writing this:
//
//   - manual/32-shell-plugins.md and shell/README.md: the plugin/manifest
//     contract (kinds, entryPoints, `~/.config/omarchy/plugins/<id>/`,
//     `omarchy plugin enable/disable`, `shell.json`'s shape).
//   - shell/Ui/BarWidget.qml, shell/Ui/Panel.qml, shell/Ui/KeyboardPanel.qml,
//     shell/Ui/PanelKeyCatcher.qml: the base types this file extends/uses.
//   - shell/plugins/panels/clock/BarWidget.qml and
//     shell/plugins/panels/power/Panel.qml: worked first-party examples of
//     exactly this "icon + click-to-open popup" shape, which this file's
//     structure mirrors (Panel base, own click target, KeyboardPanel +
//     PanelKeyCatcher for the popup, `root.bar.foreground`/`fontFamily`
//     for popup text).
//
// What is NOT confirmed:
//   - Whether a *third-party* plugin under `~/.config/omarchy/plugins/`
//     (as opposed to a first-party one under $OMARCHY_PATH/shell/plugins/)
//     can `import qs.Ui` / `import qs.Commons` the same way. The docs say
//     both locations are "discovered the same way" by the same long-running
//     `omarchy-shell` process, which implies yes, but no third-party plugin
//     source was available to confirm the import actually resolves outside
//     $OMARCHY_PATH. If it doesn't, the fix is almost certainly copying the
//     small pieces of qs.Ui this file needs (Panel, KeyboardPanel,
//     PanelKeyCatcher) into this plugin's own directory instead of
//     importing the shell's copy -- confirm this first in the VM.
//   - qs.Commons' `Color`/`Style` singletons (docs/theming.md, issue #48):
//     now used directly below (Color.accent/Color.muted/Color.urgent/
//     Color.background, Style.font.family) instead of literal hex --
//     their exact property names are confirmed, fetched directly from
//     shell/Commons/Color.qml, shell/Commons/Style.qml, and
//     shell/Commons/qmldir (`module qs.Commons` / `singleton Color 1.0` /
//     `singleton Style 1.0`) at tag v4.0.2. Still NOT used: qs.Ui's
//     `BarIconButton`/`WidgetButton` (their exact property names weren't
//     needed once this file already had its own working icon row --
//     I-6 only requires an honest, working control, not a rewrite for
//     its own sake).
//   - Keyboard reach: Keys.onReturnPressed/onEnterPressed below assume the
//     bar can hand keyboard focus to a widget (e.g. Tab-cycling bar icons).
//     Unconfirmed against a real bar; harmless if unused since a mouse
//     click always opens the menu too (I-5 still holds once the menu is
//     open: PanelKeyCatcher's arrows/Enter/Escape are real, sourced code).
// ===========================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
    id: root
    moduleName: "omarchy-kids.bar"
    ipcTarget: "omarchy-kids.bar"

    // --- external commands, every path overridable for tests/dev ----------
    readonly property string statusPath: Quickshell.env("OMARCHY_KIDS_STATUS_JSON") || "/run/omarchy-kids/status.json"
    readonly property string askBin: Quickshell.env("OMARCHY_KIDS_ASK_BIN") || "omarchy-kids-ask"
    readonly property string barCtlBin: Quickshell.env("OMARCHY_KIDS_BAR_BIN") || "omarchy-kids-bar"
    readonly property string kidsBin: Quickshell.env("OMARCHY_KIDS_BIN") || "omarchy-kids"
    // How many more minutes one click grants (bin/omarchy-kids-time grant
    // takes any positive integer; this is just this menu's one-click amount).
    readonly property int grantMinutes: 15

    // --- status.json (R-BAR-3) ---------------------------------------------
    property bool hasFile: false
    property var liveKids: []   // [{kid, initial, minutesLeft, paused}]
    property int openRequestCount: 0
    property int cursorIndex: 0

    FileView {
        id: statusFile
        path: root.statusPath
        watchChanges: true
        onLoaded: root.reloadStatus()
        onTextChanged: root.reloadStatus()
    }

    // Renders nothing when the file is missing or unreadable (I-6: no
    // control shown for data that isn't there) -- same defensive
    // try/catch-around-text() shape share/launcher/shell.qml uses, since
    // whether a missing FileView.path throws or just returns "" was not
    // confirmed either.
    function reloadStatus() {
        var text = ""
        try {
            text = statusFile.text()
        } catch (e) {
            text = ""
        }
        if (!text || text.length === 0) {
            root.hasFile = false
            root.liveKids = []
            return
        }
        var data
        try {
            data = JSON.parse(text)
        } catch (e) {
            root.hasFile = false
            root.liveKids = []
            return
        }
        root.hasFile = true
        var rows = (data && data.kids) || []
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i] || {}
            if (row.live !== true) continue
            out.push({
                kid: String(row.kid || ""),
                slug: kidSlug(row.kid),
                initial: kidInitial(row.kid),
                minutesLeft: Math.max(0, Math.round(Number(row.minutes_left) || 0)),
                paused: row.paused === true
            })
        }
        root.liveKids = out
        if (root.cursorIndex >= root.menuRows.length) root.cursorIndex = 0
    }

    function kidSlug(kid) {
        var s = String(kid || "")
        return s.indexOf("kid-") === 0 ? s.slice(4) : s
    }

    function kidInitial(kid) {
        var s = kidSlug(kid)
        return s.length > 0 ? s.charAt(0).toUpperCase() : "?"
    }

    // --- open request badge (a Process every 30s, per the issue) ----------
    // `omarchy-kids-ask list` prints a plain aligned table (ID/KID/KIND/
    // WHAT/ASKED_AT header + one row per open request) or the literal line
    // "omarchy-kids-ask: no open requests" -- there is no --json/--count
    // (bin/omarchy-kids-ask), so this counts lines instead of adding a new
    // output mode to a command another issue owns.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: askProcess.running = true
    }

    Process {
        id: askProcess
        command: [root.askBin, "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseAskCount(text)
        }
    }

    function parseAskCount(text) {
        var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
        if (lines.length === 0 || lines[0].indexOf("no open requests") !== -1) {
            root.openRequestCount = 0
            return
        }
        // First line is the header row (ID KID KIND WHAT ASKED_AT); every
        // line after it is one open request.
        root.openRequestCount = Math.max(0, lines.length - 1)
    }

    // --- menu rows: R-BAR-2's three actions ("give more time, end
    //     session, open Kids Mode") -- the first two per live kid (with
    //     that kid's own status line, R-BAR-1's "Ada · paused · 32 min"),
    //     plus the open-requests row this widget also carries (SPEC.md's
    //     Ask flow: "queue -> panel or bar widget approve") ------------
    readonly property var menuRows: {
        var rows = []
        for (var i = 0; i < liveKids.length; i++) {
            var k = liveKids[i]
            var status = k.paused ? "paused" : "live"
            var who = k.initial + " " + k.slug + " · " + status + " · " + k.minutesLeft + " min"
            rows.push({
                kind: "grant",
                kid: k.kid,
                label: who + " — give " + root.grantMinutes + " more"
            })
            rows.push({
                kind: "end",
                kid: k.kid,
                label: who + " — end session"
            })
        }
        rows.push({
            kind: "requests",
            label: "Open requests" + (openRequestCount > 0 ? " (" + openRequestCount + ")" : "")
        })
        rows.push({ kind: "open", label: "Open Kids Mode" })
        return rows
    }

    // --- actions: shell out, never block the widget ------------------------
    Process { id: actionProcess }

    function runDetached(argv) {
        actionProcess.command = argv
        actionProcess.running = true
    }

    // Neither "give N more minutes" nor "end session" ever runs
    // bin/omarchy-kids-time or loginctl directly from here -- both need
    // root, and this widget runs in the parent's ordinary, unprivileged
    // session. bin/omarchy-kids-bar grant/end is the one place that
    // decides how to open a real terminal for the sudo prompt (parent's
    // own login password, I-8) -- see that command's own header for why.
    function activateRow(row) {
        if (!row) return
        if (row.kind === "grant") {
            root.runDetached([root.barCtlBin, "grant", row.kid, String(root.grantMinutes)])
        } else if (row.kind === "end") {
            root.runDetached([root.barCtlBin, "end", row.kid])
        } else if (row.kind === "requests") {
            root.runDetached([root.kidsBin, "--requests"])
        } else if (row.kind === "open") {
            root.runDetached([root.kidsBin])
        }
        root.close()
    }

    // --- visibility: nothing to show, nothing painted -----------------------
    visible: root.hasFile && (root.liveKids.length > 0 || root.openRequestCount > 0)
    implicitWidth: root.visible ? iconRow.implicitWidth + 12 : 0
    implicitHeight: root.visible ? 22 : 0

    Row {
        id: iconRow
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: root.liveKids
            delegate: Rectangle {
                required property var modelData
                width: 16
                height: 16
                radius: 8
                color: modelData.paused ? Color.muted : Color.accent
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.initial
                    color: Color.background
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }

        Rectangle {
            visible: root.openRequestCount > 0
            width: reqBadgeText.implicitWidth + 10
            height: 16
            radius: 8
            color: Color.urgent
            Text {
                id: reqBadgeText
                anchors.centerIn: parent
                text: String(root.openRequestCount)
                color: Color.background
                font.pixelSize: 10
                font.bold: true
            }
        }
    }

    MouseArea {
        id: clickArea
        anchors.fill: parent
        onClicked: root.toggle()
    }

    Keys.onReturnPressed: root.toggle()
    Keys.onEnterPressed: root.toggle()

    KeyboardPanel {
        id: menu
        anchorItem: clickArea
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: menu.fittedContentWidth(260)
        contentHeight: menu.fittedContentHeight(rowsColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onMoveRequested: function (dx, dy) {
                if (dy === 0) return
                var n = root.menuRows.length
                if (n === 0) return
                root.cursorIndex = ((root.cursorIndex + dy) % n + n) % n
            }
            onActivateRequested: root.activateRow(root.menuRows[root.cursorIndex])
            onReturnRequested: root.activateRow(root.menuRows[root.cursorIndex])
            onCloseRequested: root.close()

            Column {
                id: rowsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 4

                Repeater {
                    model: root.menuRows
                    delegate: Rectangle {
                        id: rowDelegate
                        required property var modelData
                        required property int index
                        width: rowsColumn.width
                        height: 28
                        radius: 6
                        color: index === root.cursorIndex ? Style.selectedFillFor(Color.foreground, Color.accent, Color.urgent) : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowDelegate.modelData.label
                            elide: Text.ElideRight
                            color: root.bar ? root.bar.foreground : Color.foreground
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.cursorIndex = rowDelegate.index
                                root.activateRow(rowDelegate.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
