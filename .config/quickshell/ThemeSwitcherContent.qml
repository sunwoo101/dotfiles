// ThemeSwitcherContent — content-only theme picker (no PanelWindow).
// Hosted inside an EdgePopouts wrapper at the bottom edge with peekHeight
// set: the wrapper renders an 8 px peek strip when current === "" and
// expands to this Item's implicitHeight on hover.
//
// Inner Column fades based on the wrapper's animated panel height, so at
// peek the bg shows through without any controls visible.

import QtQuick
import QtQuick.Controls

Item {
    id: root

    implicitWidth:  560
    implicitHeight: 352

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property var mochaAccents
    required property string currentFlavor
    required property real currentOpacity
    required property real currentAnimSpeed
    required property var setAccent
    required property var toggleFlavor
    required property var clearOverride
    required property var setOpacity
    required property var setAnimSpeed

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

                    Behavior on scale { NumberAnimation { duration: Anims.accent; easing.type: Easing.OutQuad } }
                    Behavior on border.width { NumberAnimation { duration: Anims.accent } }

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
            spacing: 10
            height: 32

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "Transparency"
                color: root.cFg
                font.pixelSize: 13
                font.family: root.fontFamily
            }

            Slider {
                id: opacitySlider
                width: 240
                height: parent.height
                from: 0.2
                to: 1.0
                stepSize: 0.01
                value: root.currentOpacity

                onPressedChanged: if (!pressed) root.setOpacity(value)

                background: Rectangle {
                    x: opacitySlider.leftPadding
                    y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
                    width: opacitySlider.availableWidth
                    height: 4
                    radius: 2
                    color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)

                    Rectangle {
                        width: opacitySlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: root.cPrimary
                    }
                }

                handle: Rectangle {
                    x: opacitySlider.leftPadding + opacitySlider.visualPosition * opacitySlider.availableWidth - width / 2
                    y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
                    width: 16
                    height: 16
                    radius: 8
                    color: opacitySlider.pressed ? root.cPrimary : root.cFg
                    border.color: root.cPrimary
                    border.width: 2

                    Behavior on color { ColorAnimation { duration: Anims.micro } }
                }
            }

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: Math.round(opacitySlider.value * 100) + "%"
                color: root.cFg
                font.pixelSize: 13
                font.family: root.fontFamily
                width: 36
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            height: 32

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "Animations"
                color: root.cFg
                font.pixelSize: 13
                font.family: root.fontFamily
            }

            Slider {
                id: animSlider
                width: 240
                height: parent.height
                from: 0.1
                to: 3.0
                stepSize: 0.05
                value: root.currentAnimSpeed

                onPressedChanged: if (!pressed) root.setAnimSpeed(value)

                background: Rectangle {
                    x: animSlider.leftPadding
                    y: animSlider.topPadding + animSlider.availableHeight / 2 - height / 2
                    width: animSlider.availableWidth
                    height: 4
                    radius: 2
                    color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)

                    Rectangle {
                        width: animSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: root.cPrimary
                    }
                }

                handle: Rectangle {
                    x: animSlider.leftPadding + animSlider.visualPosition * animSlider.availableWidth - width / 2
                    y: animSlider.topPadding + animSlider.availableHeight / 2 - height / 2
                    width: 16
                    height: 16
                    radius: 8
                    color: animSlider.pressed ? root.cPrimary : root.cFg
                    border.color: root.cPrimary
                    border.width: 2

                    Behavior on color { ColorAnimation { duration: Anims.micro } }
                }
            }

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: animSlider.value.toFixed(2) + "×"
                color: root.cFg
                font.pixelSize: 13
                font.family: root.fontFamily
                width: 40
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
