// Main.qml -- the Omarchy Kids Mode SDDM portal (SPEC.md R-LOGIN-1..5,
// R-SEC-3, R-LOGIN-3, I-5; issue #14, issue #39).
// See docs/portal.md for the upstream source citations and unverified list.

import QtQuick 2.0
import Qt5Compat.GraphicalEffects

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

    // --- theme.conf.user (issues #39/#100): parent + per-kid name/avatar data,
    // parsed once at startup out of the SAME "config" QQmlPropertyMap
    // theme.conf's own colors already come through (ThemeConfig::setTo(),
    // docs/portal.md) -- no XHR, no file:// URL. A property, not an
    // inline call, so it runs once before any Repeater delegate's
    // Component.onCompleted needs it. config.kids' format
    // (lib/posture.sh's posture_portal_conf_text) is
    // "<account>:<name>:<avatar>,<account>:<name>:<avatar>,...".
    function parsePortalConfig() {
        var result = { parent: "", parents: {}, kids: {}, loaded: false }
        try {
            var parentVal = config.parent ? String(config.parent) : ""
            var parentsVal = config.parents ? String(config.parents) : ""
            var kidsVal = config.kids ? String(config.kids) : ""
            if (parentVal.length > 0 || parentsVal.length > 0 || kidsVal.length > 0) {
                result.parent = parentVal
                if (parentVal.length > 0) result.parents[parentVal] = true
                if (parentsVal.length > 0) {
                    var parentEntries = parentsVal.split(",")
                    for (var p = 0; p < parentEntries.length; p++) {
                        if (parentEntries[p].length > 0) result.parents[parentEntries[p]] = true
                    }
                }
                if (kidsVal.length > 0) {
                    var entries = kidsVal.split(",")
                    for (var i = 0; i < entries.length; i++) {
                        var parts = entries[i].split(":")
                        if (parts.length === 3 && parts[0].length > 0) {
                            result.kids[parts[0]] = { name: parts[1], avatar: parts[2] }
                        }
                    }
                }
                result.loaded = true
            }
        } catch (e) {
            // Missing or malformed config leaves both allowlists empty, so
            // no regular-account model row is admitted to the portal.
        }
        return result
    }
    readonly property var portalData: root.parsePortalConfig()
    readonly property string portalParent: portalData.parent
    readonly property var portalParents: portalData.parents
    readonly property var portalKids: portalData.kids
    readonly property bool portalLoaded: portalData.loaded === true

    // --- kid-vs-parent (R-LOGIN-1: parent tile last and smaller) --------
    // The producer writes both the profile and parent allowlists; account
    // naming is only retained for display fallback text.
    function isKidName(name) { return String(name).indexOf("kid-") === 0 }
    function isParentAccount(name) {
        return root.portalParents && root.portalParents[String(name)] === true
    }
    function isPortalUser(name) {
        return (root.portalKids && root.portalKids[String(name)] !== undefined) || root.isParentAccount(name)
    }
    // displayNameFor: realName (the passwd GECOS field, set once by
    // `omarchy-kids-provision`'s `usermod -c`, docs/provision.md) wins if
    // set; else config.kids' own per-account name (set from the same
    // profile, so this only ever differs from realName if GECOS drifted
    // or a box predates issue #39's `usermod -c` call); else the account
    // name with "kid-" stripped and the first letter capitalized.
    function displayNameFor(name, realName) {
        if (realName && realName.length > 0) return realName
        var portalEntry = root.portalKids ? root.portalKids[name] : undefined
        if (portalEntry && portalEntry.name && portalEntry.name.length > 0) return portalEntry.name
        var base = isKidName(name) ? String(name).slice(4) : String(name)
        return base.length > 0 ? base.charAt(0).toUpperCase() + base.slice(1) : base
    }
    // avatarSourceFor: AccountsService's "icon" role wins if set, else the
    // same path rebuilt from config.kids' per-account avatar id. The file
    // that actually has to exist on disk for a real greeter to render it
    // is lib/posture.sh's posture_write_face_icon output, not this path
    // (docs/portal.md's "Avatars" section).
    function avatarSourceFor(modelData) {
        if (modelData.icon && modelData.icon.length > 0) return modelData.icon
        var portalEntry = root.portalKids ? root.portalKids[modelData.name] : undefined
        if (portalEntry && portalEntry.avatar && portalEntry.avatar.length > 0) {
            return "/usr/share/omarchy-kids/avatars/" + portalEntry.avatar + ".svg"
        }
        return ""
    }

    // --- harvest userModel into a plain, reorderable JS array -----------
    // userModel is a QAbstractListModel with named roles (name, realName,
    // icon, needsPassword) that a Repeater/ListView delegate receives as
    // plain context properties -- that part is standard Qt item-view
    // behavior and needs no verification. Reordering the *view* itself
    // (kids first, parent last, R-LOGIN-1) is not possible on the model
    // directly with no C++ proxy model available here, so this hidden
    // Repeater's only job is to read allowlisted rows back into root.users
    // once; the ordered tiles use that plain array, not userModel directly.
    property var users: []

    Repeater {
        model: userModel
        delegate: Item {
            Component.onCompleted: {
                var u = root.users
                if (root.isPortalUser(name)) {
                    u.push({
                        name: name,
                        realName: realName,
                        icon: icon,
                        needsPassword: needsPassword,
                        isParent: root.isParentAccount(name)
                    })
                    root.users = u
                }
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
        keyScope.forceActiveFocus() // the closed password field would otherwise keep the arrows
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
                        clip: true
                        color: tileItem.isCurrent ? root.colTileHighlight : (modelData.isParent ? root.colParentTile : root.colTile)
                        border.width: tileItem.isCurrent ? 4 : 0
                        border.color: root.colAccent

                        // Avatar from the AccountsService Icon= path, or
                        // config.kids' own avatar id if that role comes
                        // back empty (avatarSourceFor(), issue #39;
                        // docs/provision.md, R-LOGIN-1).
                        // Mask the fallback silhouette to the avatar circle.
                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            anchors.margins: 8
                            source: root.avatarSourceFor(modelData)
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            asynchronous: true
                        }

                        Rectangle {
                            id: avatarMask
                            anchors.fill: avatarImage
                            radius: width / 2
                            color: root.colText
                            visible: false
                        }

                        OpacityMask {
                            id: avatarMaskedImage
                            anchors.fill: avatarImage
                            source: avatarImage
                            maskSource: avatarMask
                            visible: avatarImage.status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImage.status !== Image.Ready
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
                                    passwordField.text = ""
                                    root.selectTile(root.currentIndex)
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
