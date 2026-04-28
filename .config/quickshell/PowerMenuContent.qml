// PowerMenuContent — content-only (no PanelWindow). Hosted inside the
// shared Popouts wrapper. Owns sizing via implicitWidth/Height so the
// wrapper morphs to fit.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    // close request — wrapper hides itself when an action fires
    signal requestClose()

    readonly property int contentWidth:  520
    readonly property int contentHeight: 160
    readonly property int padding: 14

    implicitWidth:  contentWidth
    implicitHeight: contentHeight

    Process {
        id: cmd
        running: false
    }
    function run(args) {
        cmd.running = false;
        cmd.command = args;
        cmd.running = true;
        root.requestClose();
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        columns: 5
        rowSpacing: 10
        columnSpacing: 10

        Repeater {
            model: [
                { label: "Lock",      icon: "system-lock-screen-symbolic", cmd: ["qs", "ipc", "call", "lock", "lock"] },
                { label: "Hibernate", icon: "system-hibernate-symbolic",   cmd: ["systemctl", "hibernate"] },
                { label: "Logout",    icon: "system-log-out-symbolic",     cmd: ["hyprctl", "dispatch", "exit"] },
                { label: "Reboot",    icon: "system-reboot-symbolic",      cmd: ["systemctl", "reboot"] },
                { label: "Shutdown",  icon: "system-shutdown-symbolic",    cmd: ["systemctl", "poweroff"] }
            ]

            CardButton {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root.run(modelData.cmd)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    TintedIcon {
                        Layout.alignment: Qt.AlignHCenter
                        name: modelData.icon
                        iconBase: Quickshell.env("HOME")
                            + "/.local/share/icons/Colloid-Dark/actions/symbolic/"
                        tint: root.cFg
                        size: 28
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.label
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
