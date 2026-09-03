// shell.qml -- the "Ask a parent" modal (SPEC.md R-ASK-1..3; I-5
// keyboard-complete, I-6 honest UI). Loaded standalone with
// `quickshell -p share/ask/shell.qml` by bin/omarchy-kids-ask
// (its time/app/plugin/site subcommands), which exports
// OMARCHY_KIDS_ASK_KIND/WHAT/DESC/MINUTES/BIN and OMARCHY_KIDS_ACCOUNT
// first.
//
// Reuses, line for line where it applies, the layer-shell/keyboard-focus/
// Process/execDetached shape share/exit-modal/shell.qml verified live
// against a real Hyprland+Quickshell session (docs/exit.md's "Verified
// live" section, 2026-09-02):
//   - PanelWindow + WlrLayershell.layer: WlrLayer.Overlay, and
//     WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive (without
//     this, keys reached the window underneath instead of this modal).
//   - The verifier Process reads exactly one line, so `stdinEnabled =
//     false` right after `write()` is what lets omarchy-kids-parent-auth's
//     `read -r` return instead of hanging.
//   - Any action runs via Quickshell.execDetached, never a child
//     Process, and only *after* that call does this quit -- a Process
//     started right before Qt.quit() was killed before it ran.
// UNVERIFIED specifically for *this* file: nothing beyond the above has
// actually run yet (no "Ask a parent" trigger exists on a real desktop
// to fire this modal from) -- confirm in the VM per docs/ask.md before
// trusting it in front of a kid.
//
// Two choices (R-ASK-1), never a third and never a bare pointer-only
// path (I-5):
//   - "A grown-up is here": verifies the typed password, then submits
//     the request already marked approved/by=keyboard. The actual
//     grant is applied by omarchy-kids-ask collect (root; the panel, or
//     the every-minute timer) -- never by this modal, which has no way
//     to become root just because a password matched (docs/ask.md's
//     "Judgment calls" explains why, and what that means for how this
//     message is worded: never "Done", always "soon").
//   - "Ask later": submits the request open, no password needed, and
//     says exactly R-ASK-1's text.
// Esc: closes with no side effect at all -- nothing is written,
// nothing is asked.

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

    // --- What's being asked (bin/omarchy-kids-ask sets these before
    //     exec'ing quickshell) ---------------------------------------
    property string kidAccount: Quickshell.env("OMARCHY_KIDS_ACCOUNT") || ""
    property string kind: Quickshell.env("OMARCHY_KIDS_ASK_KIND") || ""
    property string what: Quickshell.env("OMARCHY_KIDS_ASK_WHAT") || ""
    property string desc: Quickshell.env("OMARCHY_KIDS_ASK_DESC") || "this"
    property string minutes: Quickshell.env("OMARCHY_KIDS_ASK_MINUTES") || ""
    property string askBin: Quickshell.env("OMARCHY_KIDS_ASK_BIN") || "omarchy-kids-ask"

    // 0 = "A grown-up is here" (needs the password), 1 = "Ask later"
    // (doesn't). "A grown-up is here" is preselected: it's the answer
    // most requests expect, and Enter-with-nothing-typed just fails
    // verification honestly rather than silently doing the lesser thing.
    property int selectedAction: 0

    property bool locked: false
    property int wrongCount: 0
    property bool verifying: false
    property bool done: false
    property string hint: ""
    property string doneMessage: ""

    Timer {
        id: lockoutTimer
        interval: 30000
        onTriggered: {
            root.locked = false
            root.wrongCount = 0
            root.hint = ""
        }
    }

    // Shown after either path submits, so the kid actually sees it
    // before the modal closes (R-ASK-1's own wording for "Ask later";
    // see submitApproved()/submitLater() for the on-the-spot wording).
    Timer {
        id: closeTimer
        interval: 1600
        onTriggered: Qt.quit()
    }

    // omarchy-kids-parent-auth (docs/authd.md): one line of candidate
    // password on stdin, then EOF, then its exit code is the answer.
    // Never logs the password anywhere.
    Process {
        id: authProcess
        property string candidate: ""
        command: ["omarchy-kids-parent-auth"]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(candidate + "\n")
                candidate = ""
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

    // submitApproved -- "A grown-up is here" verified. Writes the
    // request pre-decided (state=approved, by=keyboard) into this kid's
    // own outbox; omarchy-kids-ask collect is what actually performs
    // it, next time it runs (the panel, or the timer within a minute --
    // see this file's header). Detached, not a child Process, matching
    // the verified-live reason in the header.
    function submitApproved() {
        var args = ["submit", root.kind, root.what, "--state", "approved", "--by", "keyboard"]
        if (root.kind === "time" && root.minutes.length > 0) {
            args = args.concat(["--minutes", root.minutes])
        }
        Quickshell.execDetached([root.askBin].concat(args))
        root.doneMessage = "Got it! " + root.desc + " will be ready very soon."
        root.done = true
        closeTimer.restart()
    }

    // submitLater -- "Ask later": no password needed, R-ASK-1's exact
    // wording ("Asked. Your grown-up will see it.").
    function submitLater() {
        var args = ["submit", root.kind, root.what, "--state", "open"]
        if (root.kind === "time" && root.minutes.length > 0) {
            args = args.concat(["--minutes", root.minutes])
        }
        Quickshell.execDetached([root.askBin].concat(args))
        root.doneMessage = "Asked. Your grown-up will see it."
        root.done = true
        closeTimer.restart()
    }

    function onVerified() {
        root.wrongCount = 0
        root.submitApproved()
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
        if (root.done || root.locked || root.verifying) return
        if (root.selectedAction === 1) {
            root.submitLater()
            return
        }
        root.verifying = true
        authProcess.candidate = passwordInput.text
        authProcess.running = true
    }

    function closeModal() {
        Qt.quit() // Esc: never mind -- nothing written, nothing asked.
    }

    // --- The card ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#99000000"

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 460
            radius: 24
            color: "#1c1f2b"
            border.color: "#3a4266"
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

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Ask a grown-up"
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: root.desc
                        color: "#c8ccdc"
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // --- Done message (either path) -- replaces the
                    //     rest of the card once submitted (I-6: no
                    //     dead controls left visible after the choice
                    //     is made) --------------------------------------
                    Text {
                        width: parent.width
                        visible: root.done
                        text: root.doneMessage
                        color: "#9ff2c0"
                        font.pixelSize: 16
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // --- Password field (I-5: focused, masked, Enter/Esc) --
                    Rectangle {
                        visible: !root.done
                        width: parent.width
                        height: 48
                        radius: 8
                        color: root.locked ? "#3a2222" : "#12141c"
                        border.color: passwordInput.activeFocus ? "#8fb8ff" : "#3a4266"
                        border.width: 2

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.margins: 12
                            echoMode: TextInput.Password
                            focus: true
                            enabled: !root.locked && !root.verifying
                            color: "white"
                            font.pixelSize: 18
                            clip: true
                        }
                    }

                    Text {
                        width: parent.width
                        visible: !root.done && root.hint.length > 0
                        text: root.hint
                        color: root.locked ? "#ffb0b0" : "#ffd27a"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // --- "A grown-up is here" / "Ask later" (R-ASK-1) ----
                    Row {
                        visible: !root.done
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Rectangle {
                            id: hereButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 0 ? "#3a4266" : "#232838"
                            border.width: root.selectedAction === 0 ? 3 : 0
                            border.color: "#8fb8ff"

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "A grown-up is here"
                                    color: "white"
                                    font.pixelSize: 15
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: "Type their password"
                                    color: "#c8ccdc"
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
                            id: laterButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 1 ? "#3a4266" : "#232838"
                            border.width: root.selectedAction === 1 ? 3 : 0
                            border.color: "#8fb8ff"

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "Ask later"
                                    color: "white"
                                    font.pixelSize: 15
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: "Your grown-up will see it"
                                    color: "#c8ccdc"
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
