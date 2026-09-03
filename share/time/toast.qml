// toast.qml — the small top-right "N minutes left" warning (SPEC.md
// R-TIME-3). Loaded standalone with `quickshell -p share/time/toast.qml`
// by bin/omarchy-kids-time's own `show_toast`, which exports
// OMARCHY_KIDS_TOAST_TEXT first and backgrounds the process (the daemon
// keeps polling while this is up).
//
// Anchors/margins (issue #40): PanelWindow anchored top+right, same as
// before, but with `margins.top: 96` instead of 24 -- clear of
// share/launcher/shell.qml's clock, which is also top-right, at
// margins.top: 24 with font.pixelSize: 28 (roughly a 40px-tall line,
// so its bottom edge sits around y=64; 96 leaves a real gap, not just
// a graze). If the launcher's clock ever moves or changes size, this
// margin is the one thing to re-check against it -- there is no
// shared layout constant between the two files to keep them in sync
// automatically.
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
// UNVERIFIED (issue #40): the 96px top margin clearing the launcher's
// clock is arithmetic from shell.qml's own anchors/font size, never
// checked against a real rendered frame of either file side by side.
// ===========================================================================

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../qml"

PanelWindow {
    id: root

    // Theme colors/font (docs/theming.md) — see share/qml/KidsTheme.qml.
    KidsTheme { id: theme }

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
        // 96, not 24: clears share/launcher/shell.qml's clock (also
        // top-right, margins.top: 24, ~40px tall) -- see this file's
        // header for the arithmetic and its UNVERIFIED status.
        top: 96
        right: 24
    }
    implicitWidth: 320
    implicitHeight: card.implicitHeight + 32
    color: "transparent"
    visible: true

    property string message: Quickshell.env("OMARCHY_KIDS_TOAST_TEXT") || ""

    // Auto-dismiss after 6s (issue #40 tightened this from the original
    // 8s) -- overridable only for a future test harness; there is no
    // env var for this today because nothing here has been run against
    // real Quickshell to confirm quitting a PanelWindow this way is
    // even the right shutdown path.
    Timer {
        interval: 6000
        running: true
        onTriggered: Qt.quit()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: 14
        color: theme.background
        border.color: Qt.lighter(theme.background, 1.6)
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
                color: theme.warning
            }

            Text {
                width: parent.width - 40
                text: root.message
                color: theme.foreground
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
