// AppLauncher — centered drop-down launcher hanging from the bar. Symmetric
// inverse top-LEFT and top-RIGHT corners that merge into the bar; rounded
// bottom-LEFT and bottom-RIGHT. Open state and IPC live in shell.qml.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
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

    readonly property int panelWidth:    640
    readonly property int panelHeight:   520
    readonly property int invRadius:     18
    readonly property int bottomRadius:  16
    readonly property int padding:       16

    anchors { top: true; left: true; right: true }
    margins.top: 0
    implicitHeight: open ? panelHeight : 0

    Behavior on implicitHeight {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    onOpenChanged: {
        if (open) {
            searchInput.text = "";
            list.selectedIndex = 0;
            Qt.callLater(() => searchInput.forceActiveFocus());
        }
    }

    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.panelWidth + root.invRadius * 2
        height: root.implicitHeight

        readonly property real safeBottomRadius:
            Math.min(root.bottomRadius, panel.height / 2)
        readonly property real safeInvRadius:
            Math.min(root.invRadius, panel.height / 2)

        // unified outline: top edge across, top-RIGHT inverse, right down,
        // bottom-RIGHT round, bottom across, bottom-LEFT round, left up,
        // top-LEFT inverse, close to start.
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
                PathLine {
                    x: root.invRadius + panel.safeBottomRadius
                    y: panel.height
                }
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

        // content
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin:   root.invRadius + root.padding
            anchors.rightMargin:  root.invRadius + root.padding
            anchors.topMargin:    root.padding
            anchors.bottomMargin: root.padding
            spacing: 12

            // search input
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 12
                color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                border.color: searchInput.activeFocus
                    ? root.cPrimary
                    : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: ""   // search glyph (Nerd Font)
                        color: root.cMuted
                        font.family: root.fontFamily
                        font.pixelSize: 16
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        selectByMouse: true
                        focus: true

                        Keys.onEscapePressed: root.requestClose()
                        Keys.onReturnPressed: list.launchSelected()
                        Keys.onEnterPressed:  list.launchSelected()
                        Keys.onDownPressed:   list.selectNext()
                        Keys.onUpPressed:     list.selectPrev()

                        Text {
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: "Search applications..."
                            color: root.cMuted
                            font.family: root.fontFamily
                            font.pixelSize: 16
                            visible: searchInput.text.length === 0
                        }
                    }
                }
            }

            // results
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                property int selectedIndex: 0

                readonly property var filtered: {
                    var query = searchInput.text.toLowerCase().trim();
                    return DesktopEntries.applications.values
                        .filter(a => !a.noDisplay)
                        .filter(a => {
                            if (!query) return true;
                            // exec's first token is usually the binary name
                            // (e.g. "nautilus %U" → "nautilus"); strip any
                            // path so /usr/bin/foo matches "foo"
                            var rawExec = (a.command && a.command[0])
                                || (a.exec || "").split(" ")[0]
                                || "";
                            var bin = rawExec.split("/").pop().toLowerCase();
                            var hay = [
                                a.name, a.genericName, a.comment, a.id,
                                bin, (a.keywords || []).join(" ")
                            ].join(" ").toLowerCase();
                            return hay.includes(query);
                        })
                        .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
                }

                model: filtered
                onFilteredChanged: selectedIndex = 0

                function selectNext() {
                    if (count > 0) selectedIndex = Math.min(selectedIndex + 1, count - 1);
                    positionViewAtIndex(selectedIndex, ListView.Contain);
                }
                function selectPrev() {
                    if (count > 0) selectedIndex = Math.max(selectedIndex - 1, 0);
                    positionViewAtIndex(selectedIndex, ListView.Contain);
                }
                function launchSelected() {
                    if (count === 0) return;
                    var app = filtered[selectedIndex];
                    if (app) {
                        app.execute();
                        root.requestClose();
                    }
                }

                function launch(app) {
                    app.execute();
                    root.requestClose();
                }

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    implicitHeight: 52
                    radius: 10
                    color: list.selectedIndex === index
                        ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)
                        : (itemMa.containsMouse
                            ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                            : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 14

                        IconImage {
                            implicitSize: 32
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || ""
                            color: root.cFg
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.selectedIndex = index
                        onClicked: list.launch(modelData)
                    }
                }
            }
        }
    }
}
