// Bar — top bar PanelWindow per monitor.
// Receives all colors + system module state via properties from shell.qml so it
// can be moved/instantiated independently.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    required property var modelData
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property string volumeText
    required property string batteryText
    required property bool   btConnected

    screen: modelData

    readonly property int   barHeight:  38
    readonly property int   cornerSize: 16   // gaps_out (8) + window rounding (8)
    readonly property color barColor:   cBg

    anchors { top: true; left: true; right: true }
    implicitHeight: barHeight + cornerSize
    exclusiveZone:  barHeight
    color: "transparent"

    // bar background
    Rectangle {
        id: barBg
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: bar.barHeight
        color:  bar.barColor
    }

    // inverse-rounded LEFT corner
    Shape {
        width:  bar.cornerSize
        height: bar.cornerSize
        anchors { left: parent.left; top: parent.top; topMargin: bar.barHeight }
        ShapePath {
            strokeWidth: 0
            fillColor: bar.barColor
            startX: 0; startY: 0
            PathLine { x: bar.cornerSize; y: 0 }
            PathArc {
                x: 0; y: bar.cornerSize
                radiusX: bar.cornerSize; radiusY: bar.cornerSize
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 0; y: 0 }
        }
    }

    // inverse-rounded RIGHT corner
    Shape {
        width:  bar.cornerSize
        height: bar.cornerSize
        anchors { right: parent.right; top: parent.top; topMargin: bar.barHeight }
        ShapePath {
            strokeWidth: 0
            fillColor: bar.barColor
            startX: 0; startY: 0
            PathLine { x: bar.cornerSize; y: 0 }
            PathLine { x: bar.cornerSize; y: bar.cornerSize }
            PathArc {
                x: 0; y: 0
                radiusX: bar.cornerSize; radiusY: bar.cornerSize
                direction: PathArc.Counterclockwise
            }
        }
    }

    // LEFT — clock + active window title
    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter: barBg.verticalCenter
        anchors.leftMargin: 12
        spacing: 14

        Text {
            id: clock
            color: bar.cPrimary
            font.pixelSize: 13
            font.family: bar.fontFamily
            font.bold: true

            Timer {
                interval: 1000
                running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text =
                    Qt.formatDateTime(new Date(), "HH:mm  ddd dd MMM")
            }
        }

        Text {
            text: Hyprland.focusedClient ? Hyprland.focusedClient.title : ""
            color: bar.cMuted
            font.pixelSize: 12
            font.family: bar.fontFamily
            elide: Text.ElideRight
            Layout.maximumWidth: 320
        }
    }

    // CENTER — workspaces 1..10
    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: barBg.verticalCenter
        spacing: 4

        Repeater {
            model: 10

            Rectangle {
                required property int index
                readonly property int wsId: index + 1
                readonly property bool active:
                    Hyprland.focusedWorkspace
                    && Hyprland.focusedWorkspace.id === wsId

                implicitWidth: 22
                implicitHeight: 20
                radius: 4
                color: active ? bar.cPrimary : "transparent"
                border.color: bar.cMuted
                border.width: active ? 0 : 1

                Text {
                    anchors.centerIn: parent
                    text: parent.wsId
                    color: parent.active ? bar.cBg : bar.cFg
                    font.pixelSize: 12
                    font.family: bar.fontFamily
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                }
            }
        }
    }

    // RIGHT — system modules (volume + bluetooth + battery)
    RowLayout {
        anchors.right: parent.right
        anchors.verticalCenter: barBg.verticalCenter
        anchors.rightMargin: 12
        spacing: 14

        Row {
            spacing: 4
            TintedIcon {
                name: bar.volumeText === "muted"
                    ? "audio-volume-muted-symbolic"
                    : "audio-volume-high-symbolic"
                tint: bar.cFg
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: bar.volumeText
                color: bar.cFg
                font.pixelSize: 12
                font.family: bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        TintedIcon {
            name: "bluetooth-active-symbolic"
            tint: bar.cFg
            visible: bar.btConnected
        }

        Row {
            spacing: 4
            visible: bar.batteryText !== ""
            TintedIcon {
                name: "battery-good-symbolic"
                tint: bar.cFg
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: bar.batteryText
                color: bar.cFg
                font.pixelSize: 12
                font.family: bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
