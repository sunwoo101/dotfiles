// Notifications — unified popup + center. Shows recent (popped) notifications
// by default; hovering expands to all tracked notifications. Auto-sizes to
// content height, capped at maxContentHeight where it becomes scrollable.
// Right edge flush with screen, top-LEFT inverse curve merges into bar,
// bottom-LEFT rounded.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell

PanelWindow {
    id: root

    required property var  modelData
    required property var  notifServer
    required property var  popped           // list of recent notification objects
    required property var  expireCallback   // function(n) → remove from popped
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily
    required property bool open             // hovered via bell or panel

    signal panelEnter()
    signal panelLeave()

    screen: modelData
    color: "transparent"
    exclusiveZone: 0

    readonly property int contentWidth:     480
    readonly property int bottomRadius:     14
    readonly property int invRadius:        18
    readonly property int padding:          16
    readonly property int maxContentHeight: 600
    readonly property int panelTotalWidth:  contentWidth + invRadius

    // What to show: when open, ALL tracked; otherwise just recent pops. Newest
    // first.
    readonly property var displayList: {
        var src = open ? notifServer.trackedNotifications.values : popped;
        return [...src].reverse();
    }

    // Panel is visible when there's something to show (open mode also shows
    // an empty-state placeholder).
    readonly property bool hasContent: open || popped.length > 0

    anchors { top: true; right: true }
    margins.top: 0   // already below the bar's exclusive zone
    implicitWidth: panelTotalWidth

    implicitHeight: hasContent
        ? Math.min(contentColumn.implicitHeight + padding * 2, maxContentHeight)
        : 0

    Behavior on implicitHeight {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Item {
        id: panel
        anchors.fill: parent
        // fade entire panel (shape + cards) as it shrinks past the inverse-
        // corner radius — at small heights the carved-out curve collapses
        // to nothing and the shape would render as a flat rectangle.
        opacity: Math.min(1, panel.height / (root.invRadius * 2))

        readonly property real safeBottomRadius:
            Math.min(root.bottomRadius, panel.height / 2)
        readonly property real safeInvRadius:
            Math.min(root.invRadius, panel.height / 2)

        // HoverHandler — tracks hover across the full panel even when child
        // MouseAreas (e.g. close buttons) are present, unlike a parent
        // MouseArea which would lose hover when the cursor enters a child.
        HoverHandler {
            id: panelHover
            onHoveredChanged: hovered ? root.panelEnter() : root.panelLeave()
        }

        // unified outline: top edge along y=0 from (0,0) to (panel.width,0),
        // right edge flush, bottom edge with rounded bottom-LEFT, left edge
        // up to the inverse curve, inverse curve back to (0,0). One Shape
        // means no seam between body and corner.
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: 0
                fillColor: root.cBg

                startX: 0
                startY: 0

                PathLine { x: panel.width; y: 0 }
                PathLine { x: panel.width; y: panel.height }
                PathLine { x: root.invRadius + panel.safeBottomRadius; y: panel.height }
                PathArc {
                    x: root.invRadius
                    y: panel.height - panel.safeBottomRadius
                    radiusX: panel.safeBottomRadius
                    radiusY: panel.safeBottomRadius
                }
                PathLine { x: root.invRadius; y: panel.safeInvRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: panel.safeInvRadius
                    radiusY: panel.safeInvRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        // scrollable content area (right side, leaves invRadius gap on left)
        Flickable {
            id: flick
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.padding
            anchors.topMargin: root.padding
            anchors.bottomMargin: root.padding
            width: root.contentWidth - root.padding * 2

            contentHeight: contentColumn.implicitHeight
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentColumn
                width: parent.width
                spacing: 8

                Text {
                    visible: root.displayList.length === 0 && root.open
                    text: "No notifications"
                    color: root.cMuted
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    topPadding: 4
                }

                Repeater {
                    model: root.displayList

                    Rectangle {
                        id: card
                        required property var modelData

                        width: contentColumn.width
                        implicitHeight: cardCol.implicitHeight + 24
                        radius: 12
                        color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                        border.color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                        border.width: 1

                        ColumnLayout {
                            id: cardCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.appName || ""
                                    color: root.cPrimary
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    color: closeMa.containsMouse
                                        ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.18)
                                        : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.08)
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Shape {
                                        anchors.centerIn: parent
                                        width: 12
                                        height: 12
                                        ShapePath {
                                            strokeColor: closeMa.containsMouse ? root.cFg : root.cMuted
                                            strokeWidth: 1.8
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            startX: 0; startY: 0
                                            PathLine { x: 12; y: 12 }
                                        }
                                        ShapePath {
                                            strokeColor: closeMa.containsMouse ? root.cFg : root.cMuted
                                            strokeWidth: 1.8
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            startX: 12; startY: 0
                                            PathLine { x: 0; y: 12 }
                                        }
                                    }

                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.expireCallback(card.modelData);
                                            card.modelData.dismiss();
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary || ""
                                color: root.cFg
                                font.family: root.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.body || ""
                                color: root.cMuted
                                font.family: root.fontFamily
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                visible: text !== ""
                            }
                        }
                    }
                }
            }
        }
    }
}
