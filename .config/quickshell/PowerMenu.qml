// PowerMenu — drop-down panel hanging from the bar's top-LEFT, anchored to
// the left edge of the screen with an inverse top-RIGHT corner that merges
// into the bar (mirror of Notifications, which lives on the right). Open
// state and IPC live in shell.qml.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily
    required property bool open

    signal requestClose()

    screen: modelData
    color: "transparent"
    exclusiveZone: 0
    visible: implicitHeight > 0

    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.keyboardFocus: open ? WlrLayershell.OnDemand : WlrLayershell.None

    readonly property int contentWidth:  520
    readonly property int panelHeight:   160
    readonly property int invRadius:     18
    readonly property int bottomRadius:  16
    readonly property int padding:       14
    readonly property int panelTotalWidth: contentWidth + invRadius

    anchors { top: true; left: true }
    margins.top: 0
    implicitWidth:  panelTotalWidth
    implicitHeight: open ? panelHeight : 0

    Behavior on implicitHeight {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    onOpenChanged: {
        if (open) Qt.callLater(() => focusScope.forceActiveFocus());
    }

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

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.requestClose()

        Item {
            id: panel
            anchors.fill: parent

            readonly property real safeBottomRadius:
                Math.min(root.bottomRadius, panel.height / 2)
            readonly property real safeInvRadius:
                Math.min(root.invRadius, panel.height / 2)

            // unified outline: from (0,0) along the top to the inverse top-RIGHT,
            // down the right edge, rounded bottom-RIGHT, across the bottom flush
            // with the left screen edge, up the left edge to (0,0).
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.cBg

                    startX: 0
                    startY: 0

                    PathLine { x: panel.width; y: 0 }
                    PathArc {
                        x: panel.width - panel.safeInvRadius
                        y: panel.safeInvRadius
                        radiusX: panel.safeInvRadius
                        radiusY: panel.safeInvRadius
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: panel.width - root.invRadius
                        y: panel.height - panel.safeBottomRadius
                    }
                    PathArc {
                        x: panel.width - root.invRadius - panel.safeBottomRadius
                        y: panel.height
                        radiusX: panel.safeBottomRadius
                        radiusY: panel.safeBottomRadius
                    }
                    PathLine { x: 0; y: panel.height }
                    PathLine { x: 0; y: 0 }
                }
            }

            GridLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.padding
                anchors.rightMargin: root.invRadius + root.padding
                anchors.topMargin: root.padding
                anchors.bottomMargin: root.padding
                columns: 5
                rowSpacing: 10
                columnSpacing: 10

                Repeater {
                    model: [
                        { label: "Lock",     icon: "system-lock-screen-symbolic", cmd: ["qs", "ipc", "call", "lock", "lock"] },
                        { label: "Hibernate", icon: "system-hibernate-symbolic",  cmd: ["systemctl", "hibernate"] },
                        { label: "Logout",   icon: "system-log-out-symbolic",     cmd: ["hyprctl", "dispatch", "exit"] },
                        { label: "Reboot",   icon: "system-reboot-symbolic",      cmd: ["systemctl", "reboot"] },
                        { label: "Shutdown", icon: "system-shutdown-symbolic",    cmd: ["systemctl", "poweroff"] }
                    ]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: ma.containsMouse
                            ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.14)
                            : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                        border.color: ma.containsMouse
                            ? root.cPrimary
                            : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

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

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.run(modelData.cmd)
                        }
                    }
                }
            }
        }
    }
}
