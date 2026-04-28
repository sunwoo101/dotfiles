// CardButton — shared button surface used across modals and the bar.
// Subtle transparent fill, lighter fill + primary-color border on hover
// or active state. Children added to CardButton land inside the click
// area.

import QtQuick

Rectangle {
    id: btn

    required property color cFg
    required property color cPrimary

    property bool active: false
    property bool hovered: false
    readonly property bool highlighted: hovered || active

    signal clicked()

    radius: 12
    color: highlighted
        ? Qt.rgba(cFg.r, cFg.g, cFg.b, 0.18)
        : Qt.rgba(cFg.r, cFg.g, cFg.b, 0.06)
    border.color: highlighted
        ? cPrimary
        : Qt.rgba(cFg.r, cFg.g, cFg.b, 0.10)
    border.width: 1
    Behavior on color        { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    default property alias content: slot.data
    Item {
        id: slot
        anchors.fill: parent
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: btn.hovered = true
        onExited:  btn.hovered = false
        onClicked: btn.clicked()
    }
}
