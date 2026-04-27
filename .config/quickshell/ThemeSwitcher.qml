// ThemeSwitcher — bottom hover-reveal panel with accent picker + dark/light
// toggle. Receives state and action callbacks via properties so it can live in
// its own file (and a future settings UI can compose it).

import QtQuick
import QtQuick.Shapes
import Quickshell

PanelWindow {
    id: themeSwitcher

    required property var modelData
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property var mochaAccents     // list[{name, hex}]
    required property string currentFlavor // "mocha" | "latte"

    // action callbacks (passed by parent so this component stays presentation-only)
    required property var setAccent        // function(name, hex)
    required property var toggleFlavor     // function()
    required property var clearOverride    // function()

    screen: modelData

    readonly property int contentWidth:    480
    readonly property int collapsedHeight: 6
    readonly property int expandedHeight:  220
    readonly property int topRadius:       12
    readonly property int invRadius:       16
    readonly property int panelTotalWidth: contentWidth + 2 * invRadius

    property bool open: false

    anchors { bottom: true; left: true; right: true }
    implicitHeight: open ? expandedHeight : collapsedHeight
    color: "transparent"
    exclusiveZone: 0

    Behavior on implicitHeight {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: themeSwitcher.panelTotalWidth
        height: themeSwitcher.implicitHeight

        readonly property real safeTopRadius:
            Math.min(themeSwitcher.topRadius, panel.height / 2)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: themeSwitcher.open = true
            onExited:  themeSwitcher.open = false
        }

        // main panel body
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: 0
                fillColor: themeSwitcher.cBg

                startX: themeSwitcher.invRadius + panel.safeTopRadius
                startY: 0

                PathLine {
                    x: themeSwitcher.invRadius + themeSwitcher.contentWidth - panel.safeTopRadius
                    y: 0
                }
                PathArc {
                    x: themeSwitcher.invRadius + themeSwitcher.contentWidth
                    y: panel.safeTopRadius
                    radiusX: panel.safeTopRadius
                    radiusY: panel.safeTopRadius
                }
                PathLine {
                    x: themeSwitcher.invRadius + themeSwitcher.contentWidth
                    y: panel.height
                }
                PathLine { x: themeSwitcher.invRadius; y: panel.height }
                PathLine {
                    x: themeSwitcher.invRadius
                    y: panel.safeTopRadius
                }
                PathArc {
                    x: themeSwitcher.invRadius + panel.safeTopRadius
                    y: 0
                    radiusX: panel.safeTopRadius
                    radiusY: panel.safeTopRadius
                }
            }
        }

        // bottom-LEFT inverse corner
        Shape {
            anchors { left: parent.left; bottom: parent.bottom }
            width: themeSwitcher.invRadius
            height: themeSwitcher.invRadius
            opacity: panel.height > themeSwitcher.invRadius * 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            ShapePath {
                strokeWidth: 0
                fillColor: themeSwitcher.cBg
                startX: themeSwitcher.invRadius
                startY: 0
                PathLine { x: themeSwitcher.invRadius; y: themeSwitcher.invRadius }
                PathLine { x: 0; y: themeSwitcher.invRadius }
                PathArc {
                    x: themeSwitcher.invRadius; y: 0
                    radiusX: themeSwitcher.invRadius
                    radiusY: themeSwitcher.invRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        // bottom-RIGHT inverse corner
        Shape {
            anchors { right: parent.right; bottom: parent.bottom }
            width: themeSwitcher.invRadius
            height: themeSwitcher.invRadius
            opacity: panel.height > themeSwitcher.invRadius * 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            ShapePath {
                strokeWidth: 0
                fillColor: themeSwitcher.cBg
                startX: 0
                startY: 0
                PathLine { x: 0; y: themeSwitcher.invRadius }
                PathLine { x: themeSwitcher.invRadius; y: themeSwitcher.invRadius }
                PathArc {
                    x: 0; y: 0
                    radiusX: themeSwitcher.invRadius
                    radiusY: themeSwitcher.invRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        // content — title + grid + actions
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 14
            spacing: 14
            opacity: Math.max(0,
                (panel.height - themeSwitcher.collapsedHeight)
                / (themeSwitcher.expandedHeight - themeSwitcher.collapsedHeight))

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Theme Switcher"
                color: themeSwitcher.cFg
                font.pixelSize: 14
                font.family: themeSwitcher.fontFamily
                font.bold: true
            }

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 7
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: themeSwitcher.mochaAccents

                    Rectangle {
                        required property var modelData
                        readonly property bool active: themeSwitcher.cPrimary == modelData.hex

                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        color: modelData.hex
                        border.color: active ? themeSwitcher.cFg : "transparent"
                        border.width: active ? 3 : 0

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeSwitcher.setAccent(parent.modelData.name, parent.modelData.hex)
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                // dark/light toggle
                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 28
                    radius: 6
                    color: "transparent"
                    border.color: themeSwitcher.cMuted
                    border.width: 1

                    TintedIcon {
                        anchors.centerIn: parent
                        name: themeSwitcher.currentFlavor === "mocha"
                            ? "weather-clear-night-symbolic"
                            : "weather-clear-symbolic"
                        tint: themeSwitcher.cFg
                        size: 16
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeSwitcher.toggleFlavor()
                    }
                }

                // reset
                Rectangle {
                    implicitWidth: 90
                    implicitHeight: 28
                    radius: 6
                    color: "transparent"
                    border.color: themeSwitcher.cMuted
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        color: themeSwitcher.cFg
                        font.pixelSize: 12
                        font.family: themeSwitcher.fontFamily
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeSwitcher.clearOverride()
                    }
                }
            }
        }
    }
}
