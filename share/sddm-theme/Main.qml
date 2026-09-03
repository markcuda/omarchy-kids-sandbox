// Main.qml — the Omarchy Kids Mode SDDM portal (SPEC.md R-LOGIN-1..5,
// R-SEC-3, R-LOGIN-3, I-5; issue #14).
//
// ============================== UNTESTED =================================
// This has never run against a real SDDM/Qt engine -- there is no SDDM or
// Qt install on the machine this was written on, and V1
// (docs/phase1/V1.md) already found this exact stack (Omarchy 4.0.2,
// SDDM in Wayland-greeter mode, one greeter at a time). Every API used
// below is checked against upstream sddm/sddm's C++ source
// (src/greeter/*.cpp, src/common/*.cpp, data/man/sddm.conf.rst.in) and
// omacom/omarchy's own shipped theme (default/sddm/omarchy/*), both
// fetched 2026-09, not guessed:
//
//   - userModel roles: name, realName, homeDir, icon, needsPassword
//     (UserModel::roleNames(), src/greeter/UserModel.cpp), plus the
//     lastUser/lastIndex/count properties (UserModel.h).
//   - sessionModel roles: directory, file, type, name, exec, comment,
//     plus the lastIndex property (SessionModel::roleNames() /
//     ::lastIndex(), src/greeter/SessionModel.cpp). "file" is the
//     session .desktop file's *absolute path*, not a bare filename
//     (Session::fileName()/setTo(), src/common/Session.cpp) -- so the
//     lookup below matches on the path's last segment, exactly
//     "omarchy-kids.desktop" or "omarchy.desktop" (the filenames
//     desktop/omarchy-kids-session.desktop is installed as, and
//     Omarchy's own stock session file, per docs/boot.md's luks-slots
//     format and docs/session.md), never the whole path.
//   - sddm.login(user, password, sessionIndex), sddm.powerOff(),
//     sddm.canPowerOff, and the loginFailed/loginSucceeded signals
//     (src/greeter/GreeterProxy.h) -- the same three calls Omarchy's own
//     Main.qml uses.
//   - the "config" context property is a QQmlPropertyMap of theme.conf's
//     [General] keys, with no "General/" prefix on the key names (Qt's
//     QSettings special-cases that one group name) -- confirmed in
//     GreeterApp.cpp's setContextProperty("config", ...) and
//     ThemeConfig::setTo() (src/common/ThemeConfig.cpp).
//   - QQuickView is created with setResizeMode(SizeRootObjectToView)
//     (GreeterApp.cpp), so this root Item is stretched to fill the
//     screen regardless of the width/height given below -- no
//     QtQuick.Window/Screen import needed for "full-screen".
//   - metadata.desktop's QtVersion=6 and the omission of
//     "import SddmComponents" both match Omarchy's own shipped theme on
//     this exact stack; SddmComponents is skipped here on purpose (this
//     file uses no type from it) to stay dependency-light, per the
//     issue's own instruction.
//
// What is NOT confirmed, because nothing short of the real VM can check
// it (docs/portal.md has the test plan):
//   - that Image { source: <AccountsService Icon= absolute path> } loads
//     a plain "/usr/share/omarchy-kids/avatars/<id>.svg" path with no
//     "file://" prefix, and that Qt's SVG image plugin (qt6-svg) is
//     present so an SVG source rasterizes at all instead of failing
//     silently -- the fallback letter-circle below is the mitigation if
//     it doesn't.
//   - real font metrics/wrapping for long display names, and that
//     "JetBrainsMono Nerd Font" (theme.conf's default) is actually
//     installed and picked up by the greeter's own fontconfig.
//   - that Ctrl+Shift+P reaches this QML at all rather than being
//     swallowed earlier: the greeter's own minimal Hyprland config
//     (Omarchy's default/sddm/hyprland.lua, confirmed to carry no binds
//     of its own) shouldn't intercept it, but this has not been checked
//     on the real compositor.
//   - the exact shake animation timing/amplitude reads as "a shake" and
//     not jarring -- no way to eyeball this without a running greeter.
//   - R-LOGIN-5 ("the parent password opens any kid's tile") is
//     deliberately NOT implemented here: sddm.login() only ever
//     authenticates the *named* account's own password via PAM, so
//     letting the parent's password stand in for a kid's needs a
//     PAM-level change (a pam_exec line calling the R-SEC-2 verifier,
//     omarchy-kids-authd, ahead of pam_unix for kid accounts) that does
//     not exist in this checkout yet (grepped for "authd" before
//     writing this: no matches). This theme only ever submits the
//     typed password for the selected tile's own account; see
//     docs/portal.md for the follow-up this needs.
// ===========================================================================

import QtQuick 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.backgroundColor || "#1a1b26"

    // --- palette: theme.conf's [General] keys, with hardcoded fallbacks
    // so a missing/blank key never leaves a tile invisible or unreadable.
    readonly property color colTile: config.tileColor || "#232838"
    readonly property color colTileHighlight: config.tileHighlightColor || "#3a4266"
    readonly property color colParentTile: config.parentTileColor || "#1f2335"
    readonly property color colAccent: config.accentColor || "#8fb8ff"
    readonly property color colText: config.textColor || "#ffffff"
    readonly property color colMuted: config.mutedTextColor || "#9aa5ce"
    readonly property color colError: config.errorColor || "#f7768e"
    readonly property string fontFam: config.fontFamily || "JetBrainsMono Nerd Font"

    // --- kid-vs-parent (R-LOGIN-1: parent tile last and smaller) --------
    // AccountsService pins every kid account's name to "kid-<slug>"
    // (docs/provision.md, Appendix B.1); the parent is simply whoever is
    // NOT that -- this file has no other way to ask "who is the parent"
    // (machine.conf's parent= line is not reachable from QML).
    function isKidName(name) { return String(name).indexOf("kid-") === 0 }
    function displayNameFor(name, realName) {
        if (realName && realName.length > 0) return realName
        return isKidName(name) ? String(name).slice(4) : name
    }

    // --- harvest userModel into a plain, reorderable JS array -----------
    // userModel is a QAbstractListModel with named roles (name, realName,
    // icon, needsPassword) that a Repeater/ListView delegate receives as
    // plain context properties -- that part is standard Qt item-view
    // behavior and needs no verification. Reordering the *view* itself
    // (kids first, parent last, R-LOGIN-1) is not possible on the model
    // directly with no C++ proxy model available here, so this hidden
    // Repeater's only job is to read every row back into root.users once;
    // the real, ordered, on-screen tiles are the second Repeater further
    // down, bound to that plain array instead of to userModel directly.
    property var users: []

    Repeater {
        model: userModel
        delegate: Item {
            Component.onCompleted: {
                var u = root.users
                u.push({
                    name: name,
                    realName: realName,
                    icon: icon,
                    needsPassword: needsPassword,
                    isParent: !root.isKidName(name)
                })
                root.users = u
                if (index === userModel.count - 1) root.finishLoadingUsers()
            }
        }
    }

    Component.onCompleted: {
        if (userModel.count === 0) root.finishLoadingUsers()
        keyScope.forceActiveFocus()
    }

    function finishLoadingUsers() {
        var kids = root.users.filter(function (u) { return !u.isParent })
        var parents = root.users.filter(function (u) { return u.isParent })
        root.users = kids.concat(parents)
        // R-LOGIN-1: the last-used tile preselected.
        for (var i = 0; i < root.users.length; i++) {
            if (root.users[i].name === userModel.lastUser) { root.currentIndex = i; break }
        }
    }

    // --- same harvest trick for sessionModel, so a kid's Enter always
    // lands on the omarchy-kids session and the parent's on omarchy --
    // exactly what the boot-time autologin path already assumes
    // (docs/boot.md's luks-slots "guessed from the account name" rule)
    // -- and never a session picker (R-LOGIN-3). --------------------------
    property var sessionFiles: []  // [{index, base}], base = the .desktop file's basename

    Repeater {
        model: sessionModel
        delegate: Item {
            Component.onCompleted: {
                var parts = String(file).split("/")
                var s = root.sessionFiles
                s.push({ index: index, base: parts[parts.length - 1] })
                root.sessionFiles = s
            }
        }
    }

    function sessionIndexForFile(baseName) {
        for (var i = 0; i < root.sessionFiles.length; i++) {
            if (root.sessionFiles[i].base === baseName) return root.sessionFiles[i].index
        }
        return sessionModel.lastIndex
    }

    function sessionIndexForUser(user) {
        return root.sessionIndexForFile(user.isParent ? "omarchy.desktop" : "omarchy-kids.desktop")
    }

    // --- selection state --------------------------------------------------
    property int currentIndex: 0
    property bool passwordMode: false
    property bool loginFailed: false
    property int failCount: 0

    function currentUser() {
        return (root.currentIndex >= 0 && root.currentIndex < root.users.length) ? root.users[root.currentIndex] : null
    }

    function selectTile(i) {
        root.currentIndex = i
        root.passwordMode = false
        root.loginFailed = false
    }

    // Enter on the highlighted tile (R-LOGIN-2/4): "no password" profiles
    // (3-5 band only, R-SEC-3) log in immediately with an empty password;
    // every other tile opens the password field under it instead.
    function activateCurrent() {
        var u = root.currentUser()
        if (!u) return
        if (!u.needsPassword) {
            sddm.login(u.name, "", root.sessionIndexForUser(u))
            return
        }
        root.passwordMode = true
        root.loginFailed = false
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loginFailed = true
            root.failCount += 1
        }
        function onLoginSucceeded() {
            root.loginFailed = false
        }
    }

    // --- layout: tiles centered, parent last and smaller -------------------
    Row {
        id: tileRow
        anchors.centerIn: parent
        spacing: 48

        Repeater {
            model: root.users

            delegate: Item {
                id: tileItem
                property bool isCurrent: index === root.currentIndex
                property real tileSize: modelData.isParent ? 140 : 200
                property real shakeOffset: 0
                width: tileSize
                height: tileSize + 56 + (isCurrent && root.passwordMode ? 64 : 0)

                Column {
                    id: visualColumn
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    transform: Translate { x: tileItem.shakeOffset }

                    Rectangle {
                        id: avatarBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tileItem.tileSize
                        height: tileItem.tileSize
                        radius: tileItem.tileSize / 2
                        color: tileItem.isCurrent ? root.colTileHighlight : (modelData.isParent ? root.colParentTile : root.colTile)
                        border.width: tileItem.isCurrent ? 4 : 0
                        border.color: root.colAccent

                        // Avatar from the AccountsService Icon= path
                        // (docs/provision.md, R-LOGIN-1). Falls back to a
                        // plain letter circle -- see the UNTESTED note at
                        // the top of this file -- if the path is empty or
                        // fails to load (status !== Ready covers both a
                        // missing file and an SVG the image plugin can't
                        // decode).
                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            anchors.margins: 8
                            source: modelData.icon && modelData.icon.length > 0 ? modelData.icon : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !avatarImage.visible
                            text: root.displayNameFor(modelData.name, modelData.realName).charAt(0).toUpperCase()
                            color: root.colText
                            font.family: root.fontFam
                            font.pixelSize: tileItem.tileSize * 0.4
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.displayNameFor(modelData.name, modelData.realName)
                        color: modelData.isParent ? root.colMuted : root.colText
                        font.family: root.fontFam
                        font.pixelSize: modelData.isParent ? 16 : 20
                        width: tileItem.tileSize
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    // Password field, shown under the selected tile only
                    // after Enter (R-LOGIN-1/2/4). No field at all for a
                    // "no password" profile: activateCurrent() logs it in
                    // directly instead of ever setting passwordMode.
                    Rectangle {
                        visible: tileItem.isCurrent && root.passwordMode
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(tileItem.tileSize, 160)
                        height: 40
                        radius: 8
                        color: root.colTile
                        border.width: 2
                        border.color: root.loginFailed ? root.colError : root.colAccent

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.margins: 8
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: root.colText
                            font.family: root.fontFam
                            font.pixelSize: 18
                            focus: tileItem.isCurrent && root.passwordMode

                            onTextChanged: root.loginFailed = false

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    sddm.login(modelData.name, passwordField.text, root.sessionIndexForUser(modelData))
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    root.passwordMode = false
                                    passwordField.text = ""
                                    root.loginFailed = false
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                // Wrong password (R-LOGIN, "a wrong password shakes and
                // clears"): only the tile that was actually submitting
                // reacts, matched by isCurrent at the moment of failure.
                SequentialAnimation {
                    id: tileShake
                    NumberAnimation { target: tileItem; property: "shakeOffset"; to: -12; duration: 40 }
                    NumberAnimation { target: tileItem; property: "shakeOffset"; to: 12; duration: 60 }
                    NumberAnimation { target: tileItem; property: "shakeOffset"; to: -8; duration: 60 }
                    NumberAnimation { target: tileItem; property: "shakeOffset"; to: 0; duration: 40 }
                }

                Connections {
                    target: root
                    function onFailCountChanged() {
                        if (tileItem.isCurrent) {
                            passwordField.text = ""
                            tileShake.start()
                        }
                    }
                }
            }
        }
    }

    // --- keyboard (I-5: keyboard-complete) ---------------------------------
    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: (event) => {
            if (!root.passwordMode && root.currentIndex > 0) root.selectTile(root.currentIndex - 1)
            event.accepted = true
        }
        Keys.onRightPressed: (event) => {
            if (!root.passwordMode && root.currentIndex < root.users.length - 1) root.selectTile(root.currentIndex + 1)
            event.accepted = true
        }
        Keys.onReturnPressed: (event) => { if (!root.passwordMode) root.activateCurrent(); event.accepted = true }
        Keys.onEnterPressed: (event) => { if (!root.passwordMode) root.activateCurrent(); event.accepted = true }
        Keys.onEscapePressed: (event) => {
            if (root.passwordMode) root.selectTile(root.currentIndex)
            event.accepted = true
        }

        // Power-off chord (Ctrl+Alt+Del is handled elsewhere, per the
        // issue). canPowerOff mirrors upstream Main.qml's own caution
        // around calling powerOff() unconditionally (GreeterProxy.h).
        Keys.onPressed: (event) => {
            if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_P) {
                if (sddm.canPowerOff) sddm.powerOff()
                event.accepted = true
            }
        }
    }

    // --- clock ---------------------------------------------------------------
    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        color: root.colText
        font.family: root.fontFam
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
