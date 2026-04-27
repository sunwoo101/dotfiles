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
    required property int    notifCount

    signal bellEnter()
    signal bellLeave()

    screen: modelData

    readonly property int   barHeight:  48
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
        anchors.leftMargin: 14
        spacing: 16

        Text {
            id: clock
            color: bar.cPrimary
            font.pixelSize: 16
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
            font.pixelSize: 15
            font.family: bar.fontFamily
            elide: Text.ElideRight
            Layout.maximumWidth: 400
        }
    }

    // CENTER — workspaces with windows + active (Hyprland-driven, not 1..10)
    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: barBg.verticalCenter
        spacing: 6

        Repeater {
            // Hyprland.workspaces.values is the list of workspaces that exist —
            // i.e. ones with windows OR the active one. Always sorted by id.
            model: Hyprland.workspaces.values

            Rectangle {
                required property var modelData
                readonly property int wsId: modelData.id
                readonly property bool active:
                    Hyprland.focusedWorkspace
                    && Hyprland.focusedWorkspace.id === wsId

                // active = wide pill, inactive = small dot. animates smoothly.
                implicitWidth: active ? 48 : 24
                implicitHeight: 24
                radius: height / 2
                color: active
                    ? bar.cPrimary
                    : (ma.containsMouse
                        ? Qt.rgba(bar.cFg.r, bar.cFg.g, bar.cFg.b, 0.15)
                        : Qt.rgba(bar.cFg.r, bar.cFg.g, bar.cFg.b, 0.05))

                Behavior on implicitWidth {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 160 }
                }

                Text {
                    anchors.centerIn: parent
                    text: parent.wsId
                    color: parent.active ? bar.cBg : bar.cFg
                    opacity: parent.active ? 1 : 0
                    font.pixelSize: 15
                    font.family: bar.fontFamily
                    font.bold: true
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                }
            }
        }
    }

    // RIGHT — system modules (volume + bluetooth + battery + notifications)
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: barBg.verticalCenter
        anchors.rightMargin: 14
        spacing: 16

        Row {
            spacing: 6
            TintedIcon {
                name: bar.volumeText === "muted"
                    ? "audio-volume-muted-symbolic"
                    : "audio-volume-high-symbolic"
                tint: bar.cFg
                size: 20
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: bar.volumeText
                color: bar.cFg
                font.pixelSize: 15
                font.family: bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        TintedIcon {
            name: "bluetooth-active-symbolic"
            tint: bar.cFg
            size: 20
            visible: bar.btConnected
        }

        Row {
            spacing: 6
            visible: bar.batteryText !== ""
            TintedIcon {
                name: "battery-good-symbolic"
                tint: bar.cFg
                size: 20
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: bar.batteryText
                color: bar.cFg
                font.pixelSize: 15
                font.family: bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // notification indicator — bell + count. wrapper Item so MouseArea
        // can use anchors.fill (forbidden on direct Row children).
        Item {
            id: bellWrap
            implicitWidth: bellRow.implicitWidth
            implicitHeight: bellRow.implicitHeight

            Row {
                id: bellRow
                spacing: 6
                TintedIcon {
                    name: bar.notifCount > 0
                        ? "critical-notif-symbolic"
                        : "low-notif-symbolic"
                    tint: bar.cFg
                    size: 20
                }
                Text {
                    visible: bar.notifCount > 0
                    text: bar.notifCount
                    color: bar.cPrimary
                    font.pixelSize: 15
                    font.family: bar.fontFamily
                    font.bold: true
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: bar.bellEnter()
                onExited:  bar.bellLeave()
            }
        }
    }
}
