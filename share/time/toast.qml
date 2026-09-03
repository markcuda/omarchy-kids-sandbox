// toast.qml — the small top-right "N minutes left" warning (SPEC.md
// R-TIME-3). Loaded standalone with `quickshell -p share/time/toast.qml`
// by bin/omarchy-kids-time's own `show_toast`, which exports
// OMARCHY_KIDS_TOAST_TEXT first and backgrounds the process (the daemon
// keeps polling while this is up).
//
// ============================== UNTESTED =================================
// Same situation as every other Quickshell file in this repo (see
// share/exit-modal/shell.qml's header for the full disclaimer) -- no
// Quickshell install was available to check any of this against. Unlike
// the exit modal, this one is deliberately NOT keyboard-exclusive (the
// task is "a passive notice", not "stop the kid and make them answer
// something") -- omarchy-kids-time is explicit that toast.qml must not
// grab keyboard focus, so `WlrLayershell.keyboardFocus` is left at
// whatever Quickshell's default is (unset here on purpose; do not add
// `WlrKeyboardFocus.Exclusive` to this file -- that's timesup.qml's job).
// If a real Quickshell run shows this stealing focus anyway, the fix is
// almost certainly an explicit `WlrLayershell.keyboardFocus:
// WlrKeyboardFocus.None` (name unconfirmed), not adding Exclusive.
// ===========================================================================

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    // Small and out of the way: this only reserves screen space if
    // exclusiveZone is set, and a toast shouldn't shove any app's
    // content around, so leave it at Quickshell's default (0, "don't
    // reserve").
    anchors {
        top: true
        right: true
    }
    margins {
        top: 24
        right: 24
    }
    implicitWidth: 320
    implicitHeight: card.implicitHeight + 32
    color: "transparent"
    visible: true

    property string message: Quickshell.env("OMARCHY_KIDS_TOAST_TEXT") || ""

    // Auto-dismiss (the task's own words: "small, top-right, auto-
    // dismiss, no keyboard grab") -- overridable only for a future test
    // harness; there is no env var for this today because nothing here
    // has been run against real Quickshell to confirm quitting a
    // PanelWindow this way is even the right shutdown path.
    Timer {
        interval: 8000
        running: true
        onTriggered: Qt.quit()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: 14
        color: "#1c1f2b"
        border.color: "#3a4266"
        border.width: 2

        Row {
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 12

            // A plain glyph, not an icon asset: this repo ships no icon
            // font/svg set of its own for UI chrome (only
            // share/avatars/*.svg, which are per-kid, not decorative).
            Text {
                text: "⏰" // alarm clock
                font.pixelSize: 28
                color: "#ffd27a"
            }

            Text {
                width: parent.width - 40
                text: root.message
                color: "white"
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
