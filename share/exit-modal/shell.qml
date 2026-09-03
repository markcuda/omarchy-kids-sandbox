// shell.qml -- the Super+Shift+K / triple-Super-tap exit modal, loaded by
// bin/omarchy-kids-exit --open (SPEC.md R-EXIT-1..6; I-5, I-6).
// Verified live 2026-09-02 against a real Hyprland+Quickshell -- docs/exit.md.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // Theme colors/font (docs/theming.md) — see share/qml/KidsTheme.qml.
    KidsTheme { id: theme }

    // --- Layer-shell specifics (see the UNTESTED header above) -----------
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    // Verified live 2026-09-02: without this the overlay draws but keys go to the window
    // underneath (Quickshell 0.3.1 on Hyprland 0.56).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    visible: true

    // --- Who this is for (bin/omarchy-kids-exit sets these three before
    //     exec'ing quickshell; the launcher-JSON fallback below is
    //     best-effort for standalone testing and is, honestly, likely
    //     inert today -- see its own comment) ------------------------
    property string kidAccount: Quickshell.env("OMARCHY_KIDS_ACCOUNT") || ""
    property string kidName: Quickshell.env("OMARCHY_KIDS_NAME") || ""
    property string kidAvatar: Quickshell.env("OMARCHY_KIDS_AVATAR") || ""

    // Fallback source for name/avatar if the env vars above are somehow
    // unset (e.g. this file launched directly for testing, not through
    // bin/omarchy-kids-exit): the same launcher-tiles JSON
    // share/launcher/shell.qml reads. UNVERIFIED and likely a no-op in
    // practice today -- docs/levels.md's documented schema for that
    // file (account/band/level/tiles) does not currently carry a
    // "name" or "avatar" field at all, so this only starts doing
    // anything once/if a later issue adds them.
    FileView {
        id: launcherJson
        path: Quickshell.env("OMARCHY_KIDS_LAUNCHER_JSON")
            || (Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-kids/launcher-" + (Quickshell.env("UID") || "0") + ".json")
        watchChanges: false
    }
    function fallbackField(key) {
        try {
            var data = JSON.parse(launcherJson.text())
            return (data && data[key]) || ""
        } catch (e) {
            return ""
        }
    }
    property string displayName: kidName.length > 0 ? kidName : (fallbackField("name") || kidAccount)
    property string avatarSource: kidAvatar.length > 0 ? kidAvatar : fallbackField("avatar")

    // Possessive form for the sublines (R-EXIT-1): "Ada's", "Chris'".
    function possessive(name) {
        if (name.length === 0) return "Their"
        return name + (name.charAt(name.length - 1).toLowerCase() === "s" ? "'" : "'s")
    }

    // --- Pause availability (I-6: never offer a control that isn't
    //     enforced -- docs/phase1/V1.md, DECISIONS-NEEDED.md: Pause has
    //     no working mechanism yet on stock Omarchy 4.0.2). Hardcoded
    //     false, not read from the environment (review §6): a kid's own
    //     session env is theirs to set, so an env-var gate here would be
    //     a control a kid could enable themselves.
    property bool pauseAvailable: false

    // 0 = Pause, 1 = Finish. Finish is preselected while Pause is
    // unavailable: preselecting a control that refuses is exactly the
    // "honest UI" rule read backwards (I-6, review §6/§3.13). R-EXIT-1's
    // "Pause is the default" applies once Pause has a mechanism.
    property int selectedAction: root.pauseAvailable ? 0 : 1

    // --- Password / verification state -----------------------------------
    property bool locked: false
    property int wrongCount: 0
    property bool verifying: false
    property string hint: ""

    Timer {
        id: lockoutTimer
        interval: 30000
        onTriggered: {
            root.locked = false
            root.wrongCount = 0
            root.hint = ""
        }
    }

    // omarchy-kids-parent-auth (docs/authd.md): one line of candidate
    // password on stdin, then EOF, then its exit code is the answer.
    // Never logs the password anywhere -- not to a file, not to a
    // console, not left sitting in a QML property longer than the one
    // Process invocation needs it for.
    Process {
        id: authProcess
        property string candidate: ""
        command: ["/usr/bin/omarchy-kids-parent-auth"]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(candidate + "\n")
                candidate = ""
                // UNVERIFIED: however Quickshell.Io.Process actually
                // signals "no more stdin" to the child -- closeStdin()
                // is a guess. Without it, bin/omarchy-kids-parent-auth's
                // `cat -` never sees EOF and this hangs forever.
                // Quickshell 0.3.1: flipping stdinEnabled off closes the child's stdin.
                stdinEnabled = false
            }
        }
        onExited: (exitCode) => {
            root.verifying = false
            if (exitCode === 0) {
                root.onVerified()
            } else {
                root.onWrongPassword()
            }
        }
    }

    // The action itself, run only after authProcess confirms a parent
    // typed their password. Never runs with the actual command chosen
    // by anything other than root.selectedAction at the moment Enter
    // was pressed (captured into pendingAction before verification
    // starts, so a race with the highlight changing mid-check can't
    // run the wrong one).
    property string pendingAction: ""
    function onVerified() {
        root.wrongCount = 0
        // Detached, not a child Process: Qt.quit() right after starting a child
        // killed it before it ran (seen live 2026-09-02: the modal closed, the
        // session stayed). --finish ends this compositor anyway.
        Quickshell.execDetached(root.pendingAction === "finish"
            ? ["/usr/bin/omarchy-kids-exit", "--finish"]
            : ["/usr/bin/omarchy-kids-exit", "--pause"])
        Qt.quit()
    }

    function onWrongPassword() {
        root.wrongCount += 1
        passwordInput.text = ""
        shakeAnim.start()
        if (root.wrongCount >= 3) {
            root.locked = true
            root.hint = "Too many tries. Try again in 30 seconds."
            lockoutTimer.restart()
        } else {
            root.hint = "That wasn't it."
        }
    }

    function toggleSelection() {
        root.selectedAction = root.selectedAction === 0 ? 1 : 0
        root.hint = ""
    }

    function submit() {
        if (root.locked || root.verifying) return
        if (root.selectedAction === 0 && !root.pauseAvailable) {
            root.hint = "Pause isn't available yet -- press Tab, then Enter, for Finish."
            return
        }
        root.pendingAction = root.selectedAction === 0 ? "pause" : "finish"
        root.verifying = true
        authProcess.candidate = passwordInput.text
        authProcess.running = true
    }

    function closeModal() {
        Qt.quit()
    }

    // --- The card ----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: theme.dim // dim scrim over whatever was on screen

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 440
            radius: 24
            color: theme.background
            border.color: theme.cardFill
            border.width: 2
            height: cardColumn.implicitHeight + 64

            SequentialAnimation {
                id: shakeAnim
                loops: 1
                NumberAnimation { target: card; property: "x"; from: card.x; to: card.x - 12; duration: 40 }
                NumberAnimation { target: card; property: "x"; to: card.x + 24; duration: 60 }
                NumberAnimation { target: card; property: "x"; to: card.x - 16; duration: 60 }
                NumberAnimation { target: card; property: "x"; to: card.x; duration: 40 }
            }

            FocusScope {
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: (event) => { root.closeModal(); event.accepted = true }
                Keys.onTabPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onBacktabPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onReturnPressed: (event) => { root.submit(); event.accepted = true }
                Keys.onEnterPressed: (event) => { root.submit(); event.accepted = true }

                Column {
                    id: cardColumn
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: root.avatarSource
                        width: 96
                        height: 96
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.displayName
                        color: theme.foreground
                        font.pixelSize: 24
                        font.bold: true
                    }

                    // --- Password field (I-5: focused, masked, Enter/Esc) --
                    Rectangle {
                        width: parent.width
                        height: 48
                        radius: 8
                        color: root.locked ? theme.errorFill : theme.inputFill
                        border.color: passwordInput.activeFocus ? theme.accent : theme.cardFill
                        border.width: 2

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.margins: 12
                            echoMode: TextInput.Password
                            focus: true
                            enabled: !root.locked && !root.verifying
                            color: theme.foreground
                            font.pixelSize: 18
                            clip: true
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.hint.length > 0
                        text: root.hint
                        color: root.locked ? theme.error : theme.warning
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // --- Pause / Finish (R-EXIT-1) --------------------------
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Rectangle {
                            id: pauseButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 0 ? theme.tileFill : theme.cardFill
                            opacity: root.pauseAvailable ? 1.0 : 0.55
                            border.width: root.selectedAction === 0 ? 3 : 0
                            border.color: theme.accent

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "Pause " + root.displayName
                                    color: theme.foreground
                                    font.pixelSize: 16
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: root.pauseAvailable
                                        ? (root.possessive(root.displayName) + " apps stay open. You switch to your desktop.")
                                        : "Coming soon"
                                    color: theme.muted
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedAction = 0
                                    root.submit()
                                }
                            }
                        }

                        Rectangle {
                            id: finishButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 1 ? theme.tileFill : theme.cardFill
                            border.width: root.selectedAction === 1 ? 3 : 0
                            border.color: theme.accent

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "Finish for " + root.displayName
                                    color: theme.foreground
                                    font.pixelSize: 16
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: "Closes " + root.possessive(root.displayName) + " apps. You switch to your desktop."
                                    color: theme.muted
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedAction = 1
                                    root.submit()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
