// Main.qml — the Omarchy Kids Mode SDDM portal (SPEC.md R-LOGIN-1..5,
// R-SEC-3, R-LOGIN-3, I-5; issue #14, issue #39).
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
// issue #39 polish (after V1's live VM boot -- docs/portal.md's "Verified
// live" section): the greeter showed the bare account suffix ("ada",
// "cy") instead of the profile's display name, never told the parent
// tile apart from a kid's because this particular VM's *owner* account
// is itself named "kid-vm", and never rasterized an avatar. What
// changed here, and what's still unverified about each:
//   - Display name: displayNameFor() now prefers AccountsService's
//     "realName" role first (unchanged priority -- SDDM's UserModel
//     reads it from getpwnam(3)'s pw_gecos field, not from
//     AccountsService itself; omarchy-kids-provision now sets it with
//     `usermod -c`, docs/provision.md), then config.kids' own per-account
//     name (below) as a second-line fallback, then the account name with
//     "kid-" stripped and the first letter capitalized. Nothing here
//     needed a real engine to get right -- it's plain string handling --
//     but it has never actually rendered.
//   - Parent tile: no longer decided by the "kid-" username prefix at
//     all when config.parent (below) is set -- only an exact match
//     against it counts. The old prefix heuristic survives only as the
//     fallback for when config.parent is empty (see the next bullet),
//     matching every other fail-safe default in this file rather than
//     mis-rendering every tile as a parent or every tile as a kid.
//   - Parent/kids data: an EARLIER version of this fix wrote a separate
//     portal.json and read it here with a synchronous
//     XMLHttpRequest("file:///etc/omarchy-kids/portal.json"). Dropped:
//     Qt 6's own QML documentation (doc.qt.io/qt-6/qml-qtqml-
//     xmlhttprequest.html, fetched 2026-09) states plainly "By default,
//     you cannot use the XMLHttpRequest object to read files from your
//     local file system," lifted only by the process environment
//     variable QML_XHR_ALLOW_FILE_READ=1 -- and the only way found to
//     set that (a systemd drop-in on sddm.service) only takes effect
//     after `systemctl restart sddm`, which on an already-booted machine
//     re-fires the owner's stock autologin. Not worth that cost for a
//     display-name/avatar polish fix. Used instead: SDDM's OWN theme
//     config override mechanism. `ThemeConfig::setTo()`
//     (sddm/sddm's src/common/ThemeConfig.cpp, fetched 2026-09, confirmed
//     by reading it directly) loads this theme's own theme.conf into a
//     QSettings, then loads a *second* QSettings from
//     "<path-to-theme.conf>.user" and overwrites every key that second
//     file sets non-empty over the first's -- so
//     /usr/share/sddm/themes/omarchy-kids/theme.conf.user
//     (lib/posture.sh's posture_write_portal_conf, written by
//     omarchy-kids-provision, docs/portal.md) is read automatically by
//     SDDM itself before this QML ever runs, arriving here as two more
//     keys on the exact same "config" QQmlPropertyMap theme.conf's own
//     colors already come through (no XHR, no file:// URL, no extra
//     process environment needed): config.parent (the owner account) and
//     config.kids ("<account>:<Name>:<avatar>,<account>:<Name>:<avatar>,
//     ..."). parsePortalConfig() below parses that string; a blank or
//     missing config.kids/config.parent (a box with no kid provisioned
//     yet, or a stray "config" without those keys) is exactly the
//     "loaded: false" case, same fallback shape the dropped portal.json
//     design used.
//   - Avatars: Image { source: <AccountsService Icon= absolute path> }
//     loading a plain "/usr/share/omarchy-kids/avatars/<id>.svg" path
//     with no "file://" prefix, and Qt's SVG image plugin (qt6-svg)
//     being present so an SVG source rasterizes at all instead of
//     failing silently, are both still exactly as unverified as before
//     -- the fallback letter-circle below is the mitigation if either
//     isn't true; PKGBUILD now lists qt6-svg in depends= (also
//     unverified whether sddm/qt6-declarative already pull it in
//     transitively -- there is no pacman on this dev machine to check
//     with `pacman -Si sddm`). avatarSourceFor() below also falls back
//     to building that same path from config.kids' own per-account
//     avatar id when AccountsService's own icon role comes back empty,
//     for a kid provisioned before an avatar was assigned. Separately
//     (a live VM finding, not a static-analysis one): AccountsService's
//     Icon= line is not actually what SDDM's UserModel reads for the
//     avatar on this stack at all -- it checks "~/.face.icon", then
//     "/var/lib/AccountsService/icons/<account>" (a cache file nothing
//     in this repo populates), then "<FacesDir>/<account>.face.icon"
//     (UserModel.cpp, fetched 2026-09, confirmed by reading it
//     directly) -- so lib/posture.sh's posture_write_face_icon now
//     copies the avatar SVG to the third path directly; see that
//     function's own header comment for the full citation. The Image
//     element below still binds to the AccountsService icon role
//     (unchanged) since that's the only "icon" this file has any way to
//     ask userModel for; the face-icon file being right is what
//     actually makes a real greeter show it.
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

    // --- theme.conf.user (issue #39): parent + per-kid name/avatar data,
    // parsed once at startup out of the SAME "config" QQmlPropertyMap
    // theme.conf's own colors already come through (see the header
    // comment above for the ThemeConfig::setTo() citation this rests
    // on) -- no XHR, no file:// URL. "portalData" is a property (not a
    // plain function call inline below) so parsePortalConfig() runs
    // exactly once, during this Item's initial binding evaluation,
    // before any Repeater delegate's Component.onCompleted needs
    // portalParent/portalKids/portalLoaded -- QML wires up every
    // top-level property binding on an object before any
    // Component.onCompleted anywhere in its tree fires. config.kids'
    // format (lib/posture.sh's posture_portal_conf_text) is
    // "<account>:<name>:<avatar>,<account>:<name>:<avatar>,...".
    function parsePortalConfig() {
        var result = { parent: "", kids: {}, loaded: false }
        try {
            var parentVal = config.parent ? String(config.parent) : ""
            var kidsVal = config.kids ? String(config.kids) : ""
            if (parentVal.length > 0 || kidsVal.length > 0) {
                result.parent = parentVal
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
            // config.parent/config.kids missing or malformed (a box with
            // no kid provisioned yet, or a stray theme.conf.user).
            // "loaded: false" below is what every fallback here checks for.
        }
        return result
    }
    readonly property var portalData: root.parsePortalConfig()
    readonly property string portalParent: portalData.parent
    readonly property var portalKids: portalData.kids
    readonly property bool portalLoaded: portalData.loaded === true

    // --- kid-vs-parent (R-LOGIN-1: parent tile last and smaller) --------
    // Before issue #39: AccountsService pins every kid account's name to
    // "kid-<slug>" (docs/provision.md, Appendix B.1) and the parent was
    // simply whoever was NOT that. That heuristic broke on a real VM
    // whose *owner* account happened to be named "kid-vm" (docs/portal.md's
    // "Verified live" section) -- so isParentAccount() below only uses it
    // as a fallback for when theme.conf.user hasn't set config.parent at
    // all; the primary answer is an exact match against config.parent,
    // which omarchy-kids-provision derives from machine.conf's parent=
    // line, never from account naming.
    function isKidName(name) { return String(name).indexOf("kid-") === 0 }
    function isParentAccount(name) {
        if (root.portalLoaded && root.portalParent.length > 0) {
            return String(name) === root.portalParent
        }
        return !isKidName(name)
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
    // avatarSourceFor: AccountsService's own "icon" role (Icon= in
    // /var/lib/AccountsService/users/<account>, lib/posture.sh's
    // posture_accountsservice_text) wins if set; else the same path
    // rebuilt from config.kids' own per-account avatar id, for an
    // account provisioned before an avatar was assigned to it. Empty
    // string (never rendered -- avatarImage.visible checks
    // status === Ready) if neither is available. See the header comment
    // above for why the file that actually has to exist on disk for this
    // to render on a real greeter is lib/posture.sh's
    // posture_write_face_icon output, not this path.
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
                    isParent: root.isParentAccount(name)
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

                        // Avatar from the AccountsService Icon= path, or
                        // config.kids' own avatar id if that role comes
                        // back empty (avatarSourceFor(), issue #39;
                        // docs/provision.md, R-LOGIN-1). Falls back to a
                        // plain letter circle -- see the UNTESTED note at
                        // the top of this file -- if the path is empty or
                        // fails to load (status !== Ready covers both a
                        // missing file and an SVG the image plugin can't
                        // decode).
                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            anchors.margins: 8
                            source: root.avatarSourceFor(modelData)
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
