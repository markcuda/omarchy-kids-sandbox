// timesup.qml — the full-screen "Time's up" overlay (SPEC.md R-TIME-4,
// Appendix F's `grace` state; I-5 keyboard-complete, I-6 honest UI).
// Loaded standalone with `quickshell -p share/time/timesup.qml` by
// bin/omarchy-kids-time's own `show_timesup`, which exports
// OMARCHY_KIDS_ACCOUNT/NAME/AVATAR first, the same convention
// bin/omarchy-kids-exit uses for share/exit-modal/shell.qml.
//
// ============================== UNTESTED =================================
// Same disclaimer as every other Quickshell file in this repo -- see
// share/exit-modal/shell.qml's header for the full version, including
// which specific API names (PanelWindow, WlrLayershell.layer,
// WlrLayershell.keyboardFocus, Quickshell.execDetached) are the ones to
// re-check first in the VM. This file reuses exactly that same set,
// verified live for the exit modal on 2026-09-02 -- unlike the exit
// modal, this one needs no Process/stdin handling at all (neither
// button here asks for a password; see the header comment on
// bin/omarchy-kids-time's `ask-grownup` for why "Ask a grown-up" is a
// placeholder rather than a real grant today), so that whole unverified
// piece doesn't apply here.
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
    // R-TIME-4 is explicit that this screen holds the kid until they
    // answer or the grace period ends -- same reasoning as the exit
    // modal's own keyboardFocus line (verified live 2026-09-02 there).
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
    property string kidName: Quickshell.env("OMARCHY_KIDS_NAME") || ""
    property string kidAvatar: Quickshell.env("OMARCHY_KIDS_AVATAR") || ""
    property string displayName: kidName.length > 0 ? kidName : kidAccount

    // 0 = Ask a grown-up, 1 = Finish. Neither is R-EXIT-1's "Pause is
    // preselected" rule -- that's the exit modal's own default, not
    // this screen's; here Ask-a-grown-up is first because it's the
    // thing a kid actually wants to try first.
    property int selectedAction: 0

    // R-TIME-4: "terminate after 60 s unless a parent grants more."
    // This is the grace countdown -- shown, not hidden, per I-6 (a kid
    // should be able to see the clock that's about to end their
    // session, not be surprised by it).
    property int secondsLeft: 60

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.secondsLeft -= 1
            if (root.secondsLeft <= 0) {
                root.doFinish()
            }
        }
    }

    // omarchy-kids-time-ledger.timer's next tick (or a `grant` run in
    // the meantime) can clear the deficit that put this screen up;
    // bin/omarchy-kids-time's daemon loop notices that and kills this
    // process outright (`pkill -f "quickshell -p ..."`, its own
    // `dismiss_timesup`) rather than telling this file to close itself
    // -- so there is no "more time arrived" handling here at all, only
    // the two buttons and the countdown.

    function doAskGrownup() {
        // Detached, not a child Process (same reasoning as the exit
        // modal's onVerified: killing a child right after Qt.quit()
        // has been seen, live, to kill the child before it runs). This
        // does NOT close the overlay -- asking isn't the same as
        // getting (I-6: the button says "ask", not "get"), so the
        // countdown and the screen both keep going while whatever
        // omarchy-kids-time ask-grownup does happens in the background.
        Quickshell.execDetached(["omarchy-kids-time", "ask-grownup"])
    }

    function doFinish() {
        Quickshell.execDetached(["omarchy-kids-exit", "--finish"])
        Qt.quit()
    }

    function toggleSelection() {
        root.selectedAction = root.selectedAction === 0 ? 1 : 0
    }

    function activate() {
        if (root.selectedAction === 0) {
            root.doAskGrownup()
        } else {
            root.doFinish()
        }
    }

    // --- The card ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 480
            radius: 24
            color: theme.background
            border.color: Qt.lighter(theme.background, 1.6)
            border.width: 2
            height: cardColumn.implicitHeight + 64

            FocusScope {
                anchors.fill: parent
                focus: true

                // No Escape handler here on purpose: R-TIME-4's whole
                // point is that a kid can't just dismiss this and keep
                // playing (I-6 -- a control that could be waved away
                // wouldn't be honest about being enforced).
                Keys.onTabPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onBacktabPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onLeftPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onRightPressed: (event) => { root.toggleSelection(); event.accepted = true }
                Keys.onReturnPressed: (event) => { root.activate(); event.accepted = true }
                Keys.onEnterPressed: (event) => { root.activate(); event.accepted = true }

                Column {
                    id: cardColumn
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 16

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: root.kidAvatar
                        width: 96
                        height: 96
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Time's up, " + root.displayName + "!"
                        color: theme.foreground
                        font.pixelSize: 26
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: "Your screen time for today is done."
                        color: theme.muted
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Finishing in " + root.secondsLeft + "s"
                        color: root.secondsLeft <= 10 ? theme.error : theme.warning
                        font.pixelSize: 14
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Rectangle {
                            id: askButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 0 ? Qt.lighter(theme.background, 2.4) : Qt.lighter(theme.background, 1.6)
                            border.width: root.selectedAction === 0 ? 3 : 0
                            border.color: theme.accent

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "Ask a grown-up"
                                    color: theme.foreground
                                    font.pixelSize: 16
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: "for more time"
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
                                    root.activate()
                                }
                            }
                        }

                        Rectangle {
                            id: finishButton
                            width: (cardColumn.width - 16) / 2
                            height: 84
                            radius: 12
                            color: root.selectedAction === 1 ? Qt.lighter(theme.background, 2.4) : Qt.lighter(theme.background, 1.6)
                            border.width: root.selectedAction === 1 ? 3 : 0
                            border.color: theme.accent

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: "Finish"
                                    color: theme.foreground
                                    font.pixelSize: 16
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    text: "Closes " + root.displayName + "'s apps"
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
                                    root.activate()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
