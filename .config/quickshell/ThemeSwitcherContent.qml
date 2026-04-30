// ThemeSwitcherContent — content-only theme picker (no PanelWindow).
// Hosted inside an EdgePopouts wrapper at the bottom edge with peekHeight
// set: the wrapper renders an 8 px peek strip when current === "" and
// expands to this Item's implicitHeight on hover.
//
// Inner Column fades based on the wrapper's animated panel height, so at
// peek the bg shows through without any controls visible.

import QtQuick

Item {
    id: root

    implicitWidth:  560
    implicitHeight: 260

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property var mochaAccents
    required property string currentFlavor
    required property var setAccent
    required property var toggleFlavor
    required property var clearOverride

    // Wrapper-driven values for the peek-fade ratio. panelVisibleHeight
    // is the wrapper's animated panel height; peekHeight is its resting
    // collapsed value.
    required property real panelVisibleHeight
    required property real peekHeight

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 14
        spacing: 14
        opacity: Math.max(0,
            (root.panelVisibleHeight - root.peekHeight)
            / (root.implicitHeight - root.peekHeight))

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Theme Switcher"
            color: root.cFg
            font.pixelSize: 17
            font.family: root.fontFamily
            font.bold: true
        }

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: root.mochaAccents

                Rectangle {
                    required property var modelData
                    readonly property bool active: root.cPrimary == modelData.hex

                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 22
                    color: modelData.hex
                    scale: aMa.containsMouse ? 1.12 : 1.0
                    border.color: active ? root.cFg : "transparent"
                    border.width: active ? 3 : 0

                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                    Behavior on border.width { NumberAnimation { duration: 140 } }

                    MouseArea {
                        id: aMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setAccent(parent.modelData.name, parent.modelData.hex)
                    }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            CardButton {
                implicitWidth: 48
                implicitHeight: 38
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root.toggleFlavor()

                TintedIcon {
                    anchors.centerIn: parent
                    name: root.currentFlavor === "mocha"
                        ? "weather-clear-night-symbolic"
                        : "weather-clear-symbolic"
                    tint: root.cFg
                    size: 20
                }
            }

            CardButton {
                implicitWidth: 120
                implicitHeight: 38
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root.clearOverride()

                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: root.cFg
                    font.pixelSize: 14
                    font.family: root.fontFamily
                }
            }
        }
    }
}
