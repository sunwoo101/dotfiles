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
    required property bool   notifOpen
    required property bool   powerOpen
    required property bool   volumeOpen
    required property bool   calendarOpen

    // Single popout-name signal — Bar fires this when the cursor enters
    // an icon's hover area; shellRoot dispatches into popoutEnter(name).
    // popoutLeave fires when the cursor leaves the entire bar.
    signal popoutEnter(string name)
    signal popoutLeave()

    // Screen-relative anchor X positions, used by Popouts.qml.
    // Right-side popouts pin their right edge here:
    readonly property real volumeRightX:
        rightSection.x + rightRow.x + volWrap.x + volWrap.width
    readonly property real bellRightX:
        rightSection.x + rightRow.x + bellWrap.x + bellWrap.width
    // Left-side popouts pin their left edge here:
    readonly property real clockLeftX:
        leftSection.x + clock.x
    readonly property real powerLeftX: 0   // power menu hangs from screen left

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
        // layer rendering forces a repaint when fillColor changes — without
        // this, Shape caches the geometry and only repaints on geometry
        // changes, leaving the fallback color stuck after cBg updates.
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
            startX: 0 + bar.barColor.r * 0
            startY: 0
            PathLine { x: bar.cornerSize; y: 0 }
            PathLine { x: bar.cornerSize; y: bar.cornerSize }
            PathArc {
                x: 0; y: 0
                radiusX: bar.cornerSize; radiusY: bar.cornerSize
                direction: PathArc.Counterclockwise
            }
        }
    }

    // LEFT — power button + clock + active window title.
    // Wrapped in a section Item with a HoverHandler so cursor crossing
    // BETWEEN power and clock keeps the popout open (mirrors right side).
    Item {
        id: leftSection
        anchors.left: parent.left
        anchors.verticalCenter: barBg.verticalCenter
        anchors.leftMargin: 14
        implicitWidth: leftRow.implicitWidth
        implicitHeight: bar.barHeight

    RowLayout {
        id: leftRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        spacing: 16

        Item {
            implicitWidth: 28
            implicitHeight: 28
            Layout.alignment: Qt.AlignVCenter

            TintedIcon {
                anchors.centerIn: parent
                name: "system-shutdown-symbolic"
                tint: (powerMa.containsMouse || bar.powerOpen)
                    ? bar.cPrimary : bar.cFg
                size: 20
                Behavior on tint { ColorAnimation { duration: 120 } }
            }

            MouseArea {
                id: powerMa
                anchors.fill: parent
                anchors.topMargin: -(bar.barHeight - 28) / 2
                anchors.bottomMargin: -(bar.barHeight - 28) / 2
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: bar.popoutEnter("power")
                onExited:  bar.popoutLeave()
            }
        }

        Text {
            id: clock
            color: (clockMa.containsMouse || bar.calendarOpen) ? bar.cPrimary : bar.cFg
            font.pixelSize: 16
            font.family: bar.fontFamily
            font.bold: true
            Behavior on color { ColorAnimation { duration: 120 } }

            Timer {
                interval: 1000
                running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text =
                    Qt.formatDateTime(new Date(), "HH:mm  ddd dd MMM")
            }

            // hover area for the clock — extends to full bar height with
            // small horizontal padding so the cursor doesn't have to land
            // precisely on the text.
            MouseArea {
                id: clockMa
                anchors.fill: parent
                anchors.topMargin: -(bar.barHeight - parent.implicitHeight) / 2
                anchors.bottomMargin: -(bar.barHeight - parent.implicitHeight) / 2
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: bar.popoutEnter("calendar")
                onExited:  bar.popoutLeave()
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
    }   // /leftSection

    // CENTER — workspaces with windows + active (Hyprland-driven, not 1..10)
    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: barBg.verticalCenter
        spacing: 6

        Repeater {
            // Hyprland.workspaces.values is the list of workspaces that exist —
            // i.e. ones with windows OR the active one. Always sorted by id.
            model: Hyprland.workspaces.values

            CardButton {
                id: wsBtn
                required property var modelData
                readonly property int wsId: modelData.id
                active: Hyprland.focusedWorkspace
                    && Hyprland.focusedWorkspace.id === wsId

                cFg: bar.cFg
                cPrimary: bar.cPrimary
                radius: height / 2
                implicitWidth: active ? 48 : 24
                implicitHeight: 24

                Behavior on implicitWidth {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                onClicked: Hyprland.dispatch("workspace " + wsBtn.wsId)

                Text {
                    anchors.centerIn: parent
                    text: wsBtn.wsId
                    color: bar.cFg
                    opacity: wsBtn.active ? 1 : 0.2
                    font.pixelSize: 15
                    font.family: bar.fontFamily
                    font.bold: true
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }
    }

    // RIGHT — system modules (volume + bluetooth + battery + notifications).
    // The whole right Row sits inside a HoverHandler-wrapped Item so the
    // popout stays open while the cursor crosses BETWEEN icons (volume →
    // bluetooth → battery → bell). Per-icon MouseAreas only set WHICH
    // popout to show; the wrapper decides whether to keep it open.
    Item {
        id: rightSection
        anchors.right: parent.right
        anchors.verticalCenter: barBg.verticalCenter
        anchors.rightMargin: 14
        implicitWidth: rightRow.implicitWidth
        implicitHeight: bar.barHeight

    Row {
        id: rightRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        spacing: 16

        // volume icon + level — hover opens the volume/MPRIS modal.
        Item {
            id: volWrap
            implicitWidth: volRow.implicitWidth
            implicitHeight: volRow.implicitHeight

            Row {
                id: volRow
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                TintedIcon {
                    name: bar.volumeText === "muted"
                        ? "audio-volume-muted-symbolic"
                        : "audio-volume-high-symbolic"
                    tint: (volMa.containsMouse || bar.volumeOpen)
                        ? bar.cPrimary : bar.cFg
                    size: 20
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on tint { ColorAnimation { duration: 120 } }
                }
                Text {
                    text: bar.volumeText
                    color: (volMa.containsMouse || bar.volumeOpen)
                        ? bar.cPrimary : bar.cFg
                    font.pixelSize: 15
                    font.family: bar.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
            MouseArea {
                id: volMa
                anchors.fill: parent
                anchors.topMargin: -(bar.barHeight - volRow.implicitHeight) / 2
                anchors.bottomMargin: -(bar.barHeight - volRow.implicitHeight) / 2
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                hoverEnabled: true
                onEntered: bar.popoutEnter("volume")
                onExited:  bar.popoutLeave()
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
                    tint: (bellMa.containsMouse || bar.notifOpen)
                        ? bar.cPrimary : bar.cFg
                    size: 20
                    Behavior on tint { ColorAnimation { duration: 120 } }
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
            // Same trick as the power icon — extend the hit-box via
            // negative margins so the layout stays at content size.
            MouseArea {
                id: bellMa
                anchors.fill: parent
                anchors.topMargin: -(bar.barHeight - bellRow.implicitHeight) / 2
                anchors.bottomMargin: -(bar.barHeight - bellRow.implicitHeight) / 2
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                hoverEnabled: true
                onEntered: bar.popoutEnter("notifications")
                onExited:  bar.popoutLeave()
            }
        }
    }
    }
}
