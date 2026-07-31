// Lock — ext-session-lock-v1 lock screen via WlSessionLock. PAM auth via
// Quickshell.Services.Pam (config: "login"). One instance for the whole shell;
// WlSessionLock handles per-screen surfaces internally.
//
// Animation: the wayland session-lock protocol blackouts the desktop the
// instant `locked=true`, so a fade *through* the lock surface is impossible.
// Instead we use a pre-lock overlay (PanelWindow at WlrLayershell.Overlay,
// one per screen) that fades from transparent to cBg over the desktop, THEN
// engage the wayland lock. Unlock reverses: content fades out, drop the
// wayland lock, overlay fades back to transparent revealing the desktop.
//
// Trigger: shellRoot.lockObj.lock() or `qs ipc call lock lock`.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Item {
    id: lockRoot

    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property color cRed
    required property string fontFamily

    property string errorMsg: ""
    property bool authenticating: false

    // appearAmount drives the lock-surface content (clock + input). bgOpacity
    // drives the pre-lock overlay that handles the desktop ↔ cBg crossfade.
    property real appearAmount: 0
    property real bgOpacity: 0

    SequentialAnimation {
        id: lockSeq
        // 1. overlay fades up over the desktop (cBg covers desktop)
        NumberAnimation {
            target: lockRoot
            property: "bgOpacity"
            from: 0; to: 1
            duration: Anims.panel
            easing.type: Easing.OutCubic
        }
        // 2. swap overlay → lock surface (both cBg, seamless)
        ScriptAction { script: sessionLock.locked = true }
        // 3. lock-surface content fades in
        NumberAnimation {
            target: lockRoot
            property: "appearAmount"
            from: 0; to: 1
            duration: Anims.panel
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: unlockSeq
        // 1. lock-surface content fades out
        NumberAnimation {
            target: lockRoot
            property: "appearAmount"
            from: 1; to: 0
            duration: 200
            easing.type: Easing.InCubic
        }
        // 2. drop wayland lock — overlay (still bgOpacity=1) takes over
        ScriptAction { script: sessionLock.locked = false }
        // 3. overlay fades down, desktop reveals
        NumberAnimation {
            target: lockRoot
            property: "bgOpacity"
            from: 1; to: 0
            duration: Anims.panel
            easing.type: Easing.InCubic
        }
    }

    function lock() {
        if (sessionLock.locked) return;
        appearAmount = 0;
        bgOpacity = 0;
        lockSeq.start();
    }

    // Power actions available without unlocking. Same command set as
    // PowerMenuContent minus Lock (already locked) and Logout (would tear
    // down the session out from under the lock surface).
    Process {
        id: powerCmd
        running: false
    }
    function runPower(args) {
        powerCmd.running = false;
        powerCmd.command = args;
        powerCmd.running = true;
    }

    PamContext {
        id: pam
        config: "login"

        property string currentPassword: ""

        onCompleted: result => {
            lockRoot.authenticating = false;
            if (result === PamResult.Success) {
                lockRoot.errorMsg = "";
                unlockSeq.start();   // fades content, drops lock, fades overlay
            } else if (result === PamResult.MaxTries) {
                lockRoot.errorMsg = "Too many failed attempts";
            } else {
                lockRoot.errorMsg = "Authentication failed";
            }
            currentPassword = "";
        }

        onPamMessage: {
            if (responseRequired) respond(currentPassword);
        }
    }

    function tryAuth(password) {
        if (authenticating || password.length === 0) return;
        lockRoot.errorMsg = "";
        lockRoot.authenticating = true;
        pam.currentPassword = password;
        pam.start();
    }

    // Pre-lock overlay — covers each screen. While bgOpacity > 0 and the
    // wayland lock is NOT engaged, this layer is what the user sees fading
    // up over the desktop or fading away to reveal it. Hidden once the
    // wayland lock takes over (the lock surface is identical-color).
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: lockRoot.bgOpacity > 0 && !sessionLock.locked
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true; bottom: true }

            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.keyboardFocus: WlrLayershell.None

            Rectangle {
                anchors.fill: parent
                color: lockRoot.cBg
                opacity: lockRoot.bgOpacity
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            id: surface
            // Opaque cBg — must match the overlay's terminal color so the
            // overlay→lock-surface handoff has no flicker.
            color: lockRoot.cBg

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 24
                width: 360
                opacity: lockRoot.appearAmount
                scale: 0.96 + lockRoot.appearAmount * 0.04
                transformOrigin: Item.Center

                Text {
                    id: clock
                    Layout.alignment: Qt.AlignHCenter
                    color: lockRoot.cFg
                    font.family: lockRoot.fontFamily
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
                    color: lockRoot.cMuted
                    font.family: lockRoot.fontFamily
                    font.pixelSize: 18

                    Timer {
                        interval: 60000
                        running: true; repeat: true; triggeredOnStart: true
                        onTriggered: dateText.text =
                            Qt.formatDateTime(new Date(), "dddd, d MMMM")
                    }
                }

                Item { Layout.preferredHeight: 8 }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 320
                    implicitHeight: 48
                    radius: 12
                    color: Qt.rgba(lockRoot.cFg.r, lockRoot.cFg.g, lockRoot.cFg.b, 0.08)
                    border.color: pwInput.activeFocus
                        ? lockRoot.cPrimary
                        : Qt.rgba(lockRoot.cFg.r, lockRoot.cFg.g, lockRoot.cFg.b, 0.12)
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Anims.micro } }

                    TextInput {
                        id: pwInput
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        color: lockRoot.cFg
                        font.family: lockRoot.fontFamily
                        font.pixelSize: 16
                        selectByMouse: true
                        focus: true
                        enabled: !lockRoot.authenticating

                        Keys.onReturnPressed: lockRoot.tryAuth(text)
                        Keys.onEnterPressed:  lockRoot.tryAuth(text)
                        Keys.onEscapePressed: text = ""

                        Component.onCompleted: forceActiveFocus()

                        Text {
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: lockRoot.authenticating
                                ? "Authenticating…"
                                : "Password"
                            color: lockRoot.cMuted
                            font: pwInput.font
                            visible: pwInput.text.length === 0
                        }

                        Connections {
                            target: pam
                            function onCompleted(result) {
                                if (result !== PamResult.Success) pwInput.text = "";
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lockRoot.errorMsg
                    color: lockRoot.cRed
                    font.family: lockRoot.fontFamily
                    font.pixelSize: 14
                    visible: lockRoot.errorMsg.length > 0
                }

                // Power actions. Round CardButtons, icon-only — placed below
                // the input so they can't be fat-fingered while reaching for
                // Enter. Disabled mid-auth so a click can't race PAM.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    spacing: 12

                    Repeater {
                        model: [
                            { icon: "system-hibernate-symbolic", cmd: ["systemctl", "hibernate"] },
                            { icon: "system-reboot-symbolic",    cmd: ["systemctl", "reboot"]    },
                            { icon: "system-shutdown-symbolic",  cmd: ["systemctl", "poweroff"]  }
                        ]

                        CardButton {
                            required property var modelData
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: height / 2
                            cFg: lockRoot.cFg
                            cPrimary: lockRoot.cPrimary
                            enabled: !lockRoot.authenticating
                            opacity: lockRoot.authenticating ? 0.4 : 1
                            Behavior on opacity { NumberAnimation { duration: Anims.micro } }
                            onClicked: lockRoot.runPower(modelData.cmd)

                            TintedIcon {
                                anchors.centerIn: parent
                                name: modelData.icon
                                iconBase: Quickshell.env("HOME")
                                    + "/.local/share/icons/Colloid-Dark/actions/symbolic/"
                                tint: lockRoot.cFg
                                size: 20
                            }
                        }
                    }
                }
            }
        }
    }
}
