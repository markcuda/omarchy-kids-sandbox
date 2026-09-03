// shell.qml — the kid-facing Wi-Fi picker (SPEC.md R-WIFI-1..2; I-5
// keyboard-complete, I-6 honest UI). Loaded standalone with
// `quickshell -p share/wifi/shell.qml` by `omarchy-kids-wifi picker`,
// which already refused (with a small toast) before ever exec'ing this
// if the caller's profile isn't wifi=helper — this file assumes it is
// only ever reached for a helper-mode kid, but never assumes that
// silently: every action below still goes through `omarchy-kids-wifi`,
// which re-checks against bin/omarchy-kids-wifid's own SO_PEERCRED-based
// authorization every single time (see bin/omarchy-kids-wifi's header).
//
// ============================== UNTESTED =================================
// Same situation as every other Quickshell file in this repo — no
// Quickshell install was available to check any of this against. Two
// pieces are carried over from share/exit-modal/shell.qml, where they
// were verified live 2026-09-02 against Quickshell 0.3.1 on Hyprland
// 0.56, and are used identically here:
//
//   - `PanelWindow` + `WlrLayershell.layer: WlrLayer.Overlay` +
//     `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` — without
//     the last one, keys go to the window underneath, not this overlay.
//   - `Quickshell.Io.Process` with `stdinEnabled`/`write()`, and
//     flipping `stdinEnabled = false` (not a `closeStdin()` call) to
//     signal EOF to the child once the one line it needs has been
//     written.
//
// Everything else here is new to this file and unconfirmed:
//
//   - Running `omarchy-kids-wifi list` as a plain (non-stdin) Process
//     and reading its stdout via `Process.stdout`/a `SplitParser` or
//     similar — this repo's other Quickshell files only ever *start*
//     commands (share/launcher/shell.qml) or write to one's stdin
//     (share/exit-modal/shell.qml); none of them have read a command's
//     stdout back into QML before. `Quickshell.Io.Process.stdout` and
//     however it delivers "the process exited, here is everything it
//     printed" are both guesses.
//   - nmcli's terse (`-t`) output, which bin/omarchy-kids-wifid's LIST
//     command passes straight through, is ':'-delimited by default and
//     escapes a literal ':' inside a field with a backslash. The naive
//     `split(":")` below does NOT unescape that — an SSID containing a
//     colon will parse wrong (extra/misaligned columns). Rare in
//     practice (colons are legal but very unusual in an SSID); flagged
//     rather than silently mishandled.
// ===========================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // Theme colors/font (docs/theming.md) — see share/qml/KidsTheme.qml.
    KidsTheme { id: theme }

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

    property string kidAccount: Quickshell.env("OMARCHY_KIDS_ACCOUNT") || ""

    // --- Network list ------------------------------------------------------
    property var networks: []   // [{ssid, signal, security, inUse}]
    property int currentIndex: 0
    property bool loading: true
    property string statusText: ""
    property bool joining: false

    // "omarchy-kids-wifi list" (bin/omarchy-kids-wifi), not nmcli
    // directly — this process is unprivileged; the daemon it talks to
    // over the socket is the one thing that may run nmcli at all.
    Process {
        id: listProcess
        command: ["/usr/bin/omarchy-kids-wifi", "list"]
        property string collected: ""
        onRunningChanged: if (running) collected = ""
        stdout: SplitParser {
            onRead: (line) => { listProcess.collected += line + "\n" }
        }
        onExited: (exitCode) => {
            root.loading = false
            if (exitCode !== 0) {
                root.statusText = "Couldn't list networks. Ask a grown-up."
                root.networks = []
                return
            }
            root.networks = root.parseList(listProcess.collected)
            if (root.currentIndex >= root.networks.length) {
                root.currentIndex = Math.max(0, root.networks.length - 1)
            }
        }
    }

    function refreshList() {
        root.loading = true
        root.statusText = ""
        listProcess.running = true
    }

    // parseList TEXT -> [{ssid, signal, security, inUse}], de-duplicated
    // by SSID (the same network shows once per BSSID otherwise), sorted
    // by signal strength, strongest first. See the UNTESTED header above
    // for why plain split(":") is a known-imperfect parse of nmcli -t.
    function parseList(text) {
        var seen = {}
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if (line.length === 0) continue
            var fields = line.split(":")
            var ssid = fields[0] || ""
            if (ssid.length === 0) continue   // hidden/blank SSID: nothing to join by name
            if (seen[ssid]) continue
            seen[ssid] = true
            out.push({
                ssid: ssid,
                signal: parseInt(fields[1] || "0", 10) || 0,
                security: fields[2] || "",
                inUse: (fields[3] || "") === "*"
            })
        }
        out.sort(function(a, b) { return b.signal - a.signal })
        return out
    }

    Component.onCompleted: root.refreshList()

    function selectedNetwork() {
        if (root.currentIndex < 0 || root.currentIndex >= root.networks.length) return null
        return root.networks[root.currentIndex]
    }

    function needsPassword(net) {
        return !!net && net.security.length > 0 && net.security !== "--"
    }

    // --- Joining -------------------------------------------------------
    // "omarchy-kids-wifi join <ssid> --password-stdin" (or without the
    // flag for an open network) — same one-line-on-stdin-then-EOF shape
    // share/exit-modal/shell.qml already uses for
    // omarchy-kids-parent-auth, so this reuses the confirmed
    // stdinEnabled/write()/stdinEnabled=false sequence rather than
    // guessing a second one.
    Process {
        id: joinProcess
        property string candidate: ""
        property bool sent: false
        stdinEnabled: true
        property string collected: ""
        stdout: SplitParser {
            onRead: (line) => { joinProcess.collected += line + "\n" }
        }
        onRunningChanged: {
            if (running) {
                joinProcess.sent = false
                joinProcess.collected = ""
            }
        }
        // Only write to stdin for a network that actually needs a
        // password; an open network's "join" invocation has no
        // --password-stdin flag at all, so nothing here waits to write.
        onStdinEnabledChanged: {
            if (stdinEnabled && running && !joinProcess.sent) {
                joinProcess.write(joinProcess.candidate + "\n")
                joinProcess.candidate = ""
                joinProcess.sent = true
                joinProcess.stdinEnabled = false
            }
        }
        onExited: (exitCode) => {
            root.joining = false
            if (exitCode === 0) {
                root.statusText = "Joined " + (root.selectedNetwork() ? root.selectedNetwork().ssid : "the network") + "."
                root.showPasswordField = false
                root.passwordText = ""
                root.refreshList()
            } else if (exitCode === 3) {
                root.statusText = "Wi-Fi needs a grown-up right now."
            } else {
                root.statusText = "Couldn't join. Check the password and try again."
            }
        }
    }

    property bool showPasswordField: false
    property string passwordText: ""

    function beginJoin() {
        var net = root.selectedNetwork()
        if (!net || root.joining) return
        if (root.needsPassword(net) && !root.showPasswordField) {
            root.showPasswordField = true
            root.statusText = ""
            return
        }
        root.joining = true
        root.statusText = "Joining " + net.ssid + "…"
        if (root.needsPassword(net)) {
            joinProcess.command = ["omarchy-kids-wifi", "join", net.ssid, "--password-stdin"]
            joinProcess.candidate = root.passwordText
            joinProcess.stdinEnabled = true
        } else {
            joinProcess.command = ["omarchy-kids-wifi", "join", net.ssid]
            joinProcess.stdinEnabled = false
        }
        joinProcess.running = true
    }

    function closeOverlay() { Qt.quit() }

    // --- Keyboard (I-5: keyboard-complete) --------------------------------
    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: (event) => {
            if (root.showPasswordField) {
                root.showPasswordField = false
                root.passwordText = ""
            } else {
                root.closeOverlay()
            }
            event.accepted = true
        }
        Keys.onUpPressed: (event) => {
            if (!root.showPasswordField && root.currentIndex > 0) root.currentIndex -= 1
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            if (!root.showPasswordField && root.currentIndex + 1 < root.networks.length) root.currentIndex += 1
            event.accepted = true
        }
        Keys.onReturnPressed: (event) => { root.beginJoin(); event.accepted = true }
        Keys.onEnterPressed: (event) => { root.beginJoin(); event.accepted = true }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 480
                height: Math.min(560, cardColumn.implicitHeight + 64)
                radius: 24
                color: theme.background
                border.color: Qt.lighter(theme.background, 1.6)
                border.width: 2

                Column {
                    id: cardColumn
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.margins: 32
                    width: parent.width - 64
                    spacing: 16

                    Text {
                        text: "Wi-Fi"
                        color: theme.foreground
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        visible: root.loading
                        text: "Looking for networks…"
                        color: theme.muted
                        font.pixelSize: 14
                    }

                    ListView {
                        id: list
                        visible: !root.loading && !root.showPasswordField
                        width: parent.width
                        height: 320
                        clip: true
                        model: root.networks
                        currentIndex: root.currentIndex
                        highlightMoveDuration: 80

                        delegate: Rectangle {
                            width: list.width
                            height: 56
                            radius: 10
                            color: ListView.isCurrentItem ? Qt.lighter(theme.background, 2.4) : Qt.lighter(theme.background, 1.6)

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Text {
                                    text: modelData.ssid
                                    color: theme.foreground
                                    font.pixelSize: 16
                                    font.bold: modelData.inUse
                                    width: parent.width - 140
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.security.length > 0 ? "🔒" : "open"
                                    color: theme.muted
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: modelData.signal + "%"
                                    color: theme.muted
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.currentIndex = index
                                    root.beginJoin()
                                }
                            }
                        }
                    }

                    // --- Password step ---------------------------------
                    Column {
                        visible: root.showPasswordField
                        width: parent.width
                        spacing: 12

                        Text {
                            width: parent.width
                            text: root.selectedNetwork() ? ("Password for " + root.selectedNetwork().ssid) : ""
                            color: theme.foreground
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            width: parent.width
                            height: 48
                            radius: 8
                            color: Qt.darker(theme.background, 1.3)
                            border.color: passwordInput.activeFocus ? theme.accent : Qt.lighter(theme.background, 1.6)
                            border.width: 2

                            TextInput {
                                id: passwordInput
                                anchors.fill: parent
                                anchors.margins: 12
                                echoMode: TextInput.Password
                                focus: root.showPasswordField
                                enabled: !root.joining
                                color: theme.foreground
                                font.pixelSize: 18
                                clip: true
                                text: root.passwordText
                                onTextChanged: root.passwordText = text
                                Keys.onReturnPressed: (event) => { root.beginJoin(); event.accepted = true }
                                Keys.onEnterPressed: (event) => { root.beginJoin(); event.accepted = true }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.statusText.length > 0
                        text: root.statusText
                        color: theme.warning
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: "Enter join · Esc back/close"
                        color: theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
