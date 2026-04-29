// SDDM greeter — mirrors Lock.qml's centered clock + date + password card
// layout. Colors and font come from theme.conf (rendered from colors.json
// by scripts/render_configs.sh). Power buttons live in the bottom-right;
// user + session pickers in the bottom-left.
//
// Multi-monitor: SDDM creates a separate Main.qml instance per screen, each
// with its own state. Without gating, clicking the session/user picker on
// one screen wouldn't update the others. Solved by rendering interactive
// UI only on the primary screen (`primaryScreen` is a bool context property
// SDDM sets per-window). Non-primary screens show clock + date + bg only.
//
// Context properties available from SDDM:
//   sddm           — login(user, pwd, sessionIndex), powerOff/reboot/hibernate/suspend,
//                    canPowerOff/canReboot/canHibernate/canSuspend, signals:
//                    loginFailed, loginSucceeded, informationMessage, errorMessage
//   userModel      — name, realName, lastIndex, lastUser, count
//   sessionModel   — name, file, lastIndex, count
//   primaryScreen  — bool, true on the primary-screen instance only

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.bg

    readonly property color cBg: config.bg
    readonly property color cFg: config.fg
    readonly property color cPrimary: config.primary
    readonly property color cMuted: config.muted
    readonly property color cRed: config.red
    readonly property string fontFamily: config.fontFamily

    property string errorMsg: ""
    property bool authenticating: false

    // currentUserIndex resolves to lastUser if known, else first entry.
    // userModel.lastUser is a *name* (string) — translate to row index so
    // the cycle button can step through it.
    function _userIndexByName(name) {
        for (var i = 0; i < userModel.count; i++) {
            if (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) === name)
                return i;
        }
        return 0;
    }
    property int currentUserIndex: userModel.lastUser !== ""
        ? _userIndexByName(userModel.lastUser) : 0
    readonly property string currentUser: userModel.count > 0
        ? (userModel.data(userModel.index(currentUserIndex, 0), Qt.UserRole + 1) || "")
        : ""
    property int currentSessionIndex: sessionModel.lastIndex >= 0
        ? sessionModel.lastIndex : 0

    Connections {
        target: sddm
        function onLoginFailed() {
            root.authenticating = false;
            root.errorMsg = "Authentication failed";
            pwInput.text = "";
            pwInput.forceActiveFocus();
        }
        function onLoginSucceeded() {
            root.authenticating = false;
            root.errorMsg = "";
        }
        function onErrorMessage(msg) {
            root.errorMsg = msg;
            root.authenticating = false;
        }
    }

    function tryAuth() {
        if (root.authenticating || pwInput.text.length === 0) return;
        root.errorMsg = "";
        root.authenticating = true;
        sddm.login(root.currentUser, pwInput.text, root.currentSessionIndex);
    }

    // Centered card — matches Lock.qml's ColumnLayout
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        width: 360

        Text {
            id: clock
            Layout.alignment: Qt.AlignHCenter
            color: root.cFg
            font.family: root.fontFamily
            font.pixelSize: 96
            font.weight: Font.Light

            Timer {
                interval: 1000
                running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text =
                    Qt.formatDateTime(new Date(), "HH:mm")
            }
        }

        Text {
            id: dateText
            Layout.alignment: Qt.AlignHCenter
            color: root.cMuted
            font.family: root.fontFamily
            font.pixelSize: 18

            Timer {
                interval: 60000
                running: true; repeat: true; triggeredOnStart: true
                onTriggered: dateText.text =
                    Qt.formatDateTime(new Date(), "dddd, d MMMM")
            }
        }

        Item {
            Layout.preferredHeight: 8
            visible: primaryScreen
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.currentUser
            color: root.cFg
            font.family: root.fontFamily
            font.pixelSize: 16
            visible: primaryScreen && text.length > 0
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 320
            implicitHeight: 48
            radius: 12
            visible: primaryScreen
            color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.08)
            border.color: pwInput.activeFocus
                ? root.cPrimary
                : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 120 } }

            TextInput {
                id: pwInput
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: root.cFg
                font.family: root.fontFamily
                font.pixelSize: 16
                selectByMouse: true
                focus: true
                enabled: !root.authenticating

                Keys.onReturnPressed: root.tryAuth()
                Keys.onEnterPressed:  root.tryAuth()
                Keys.onEscapePressed: text = ""

                Component.onCompleted: forceActiveFocus()

                Text {
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.authenticating ? "Authenticating…" : "Password"
                    color: root.cMuted
                    font: pwInput.font
                    visible: pwInput.text.length === 0
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.errorMsg
            color: root.cRed
            font.family: root.fontFamily
            font.pixelSize: 14
            visible: primaryScreen && root.errorMsg.length > 0
        }
    }

    // Reusable button surface — mirrors CardButton.qml's visual contract:
    // 12 px radius, fg-tinted fill, primary border on hover.
    component CardBtn: Rectangle {
        id: btn
        property alias text: label.text
        property bool active: false
        signal clicked()

        implicitWidth: label.implicitWidth + 28
        implicitHeight: 36
        radius: 12
        readonly property bool highlighted: hover.hovered || btn.active
        color: btn.highlighted
            ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.18)
            : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
        border.width: 1
        border.color: btn.highlighted
            ? root.cPrimary
            : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.clicked() }

        Text {
            id: label
            anchors.centerIn: parent
            color: root.cFg
            font.family: root.fontFamily
            font.pixelSize: 13
        }
    }

    // Bottom-left: user + session pickers. Each is a click-to-cycle button
    // when there's more than one entry; otherwise a static label.
    RowLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 16
        visible: primaryScreen

        RowLayout {
            spacing: 8
            visible: userModel.count > 0
            Text {
                color: root.cMuted
                font.family: root.fontFamily
                font.pixelSize: 12
                text: "User"
            }
            CardBtn {
                text: root.currentUser
                onClicked: root.currentUserIndex =
                    (root.currentUserIndex + 1) % userModel.count
                visible: userModel.count > 1
            }
            Text {
                color: root.cFg
                font.family: root.fontFamily
                font.pixelSize: 13
                text: root.currentUser
                visible: userModel.count <= 1
            }
        }

        RowLayout {
            spacing: 8
            visible: sessionModel.count > 0
            Text {
                color: root.cMuted
                font.family: root.fontFamily
                font.pixelSize: 12
                text: "Session"
            }
            CardBtn {
                text: sessionModel.count > 0
                    ? (sessionModel.data(
                        sessionModel.index(root.currentSessionIndex, 0),
                        Qt.UserRole + 4) || "")
                    : ""
                onClicked: root.currentSessionIndex =
                    (root.currentSessionIndex + 1) % sessionModel.count
                visible: sessionModel.count > 1
            }
            Text {
                color: root.cFg
                font.family: root.fontFamily
                font.pixelSize: 13
                text: sessionModel.count > 0
                    ? (sessionModel.data(
                        sessionModel.index(root.currentSessionIndex, 0),
                        Qt.UserRole + 4) || "")
                    : ""
                visible: sessionModel.count <= 1
            }
        }
    }

    // Bottom-right: power buttons.
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 8
        visible: primaryScreen

        CardBtn {
            text: "Hibernate"
            visible: sddm.canHibernate
            onClicked: sddm.hibernate()
        }
        CardBtn {
            text: "Reboot"
            visible: sddm.canReboot
            onClicked: sddm.reboot()
        }
        CardBtn {
            text: "Shut down"
            visible: sddm.canPowerOff
            onClicked: sddm.powerOff()
        }
    }
}
