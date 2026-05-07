// WorkspacesContent — content-only thumbnail grid for the workspaces
// overview popout. Reads cached PNGs from shellRoot.workspaceThumbPath()
// (captured by shellRoot's grim driver). Each card shows the thumbnail,
// the workspace id label, and a click target that switches workspaces
// via Hyprland.dispatch.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily
    required property string thumbDir
    // Bumped by shellRoot whenever a new capture finishes. Used as a
    // cache-buster on the Image source so QML refetches the file.
    required property int thumbVersion

    signal requestClose()

    readonly property int thumbWidth:  220
    readonly property int thumbHeight: 124   // 16:9-ish
    readonly property int padding:     14
    readonly property int spacing:      8

    function _thumbSource(wsId) {
        return "file://" + root.thumbDir + "/" + wsId + ".png";
    }

    implicitWidth:  row.implicitWidth  + padding * 2
    implicitHeight: row.implicitHeight + padding * 2

    Row {
        id: row
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: root.spacing

        Repeater {
            // Special workspaces (negative ids) hold per-app tray windows
            // and shouldn't appear in the overview alongside normal ones.
            model: Hyprland.workspaces.values.filter(w => w.id >= 0)

            Rectangle {
                id: wsCard
                required property var modelData
                readonly property int wsId: modelData.id
                readonly property bool isActive: Hyprland.focusedWorkspace
                    && Hyprland.focusedWorkspace.id === wsId

                width:  root.thumbWidth
                height: root.thumbHeight + 26
                radius: 12
                color: cardMa.containsMouse
                    ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)
                    : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                border.color: wsCard.isActive
                    ? root.cPrimary
                    : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                border.width: 1
                Behavior on color        { ColorAnimation { duration: Anims.micro } }
                Behavior on border.color { ColorAnimation { duration: Anims.micro } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    Item {
                        width: parent.width
                        height: root.thumbHeight - 12

                        // Thumbnail. clip+scale so the image matches the
                        // card aspect; placeholder shown if no thumb yet.
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: root._thumbSource(wsCard.wsId)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            smooth: true
                            visible: status === Image.Ready
                        }
                        // QML Image won't auto-refetch when the underlying
                        // file changes if the source URL is unchanged.
                        // Bump version → reset source so it re-reads.
                        Connections {
                            target: root
                            function onThumbVersionChanged() {
                                var s = root._thumbSource(wsCard.wsId);
                                thumb.source = "";
                                thumb.source = s;
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.04)
                            visible: thumb.status !== Image.Ready
                            Text {
                                anchors.centerIn: parent
                                text: "no preview"
                                color: root.cMuted
                                font.family: root.fontFamily
                                font.pixelSize: 11
                            }
                        }
                        // round the corners of the thumbnail itself
                        layer.enabled: true
                        layer.smooth: true
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: wsCard.wsId
                        color: wsCard.isActive ? root.cPrimary : root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                MouseArea {
                    id: cardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Hyprland.dispatch("workspace " + wsCard.wsId);
                        root.requestClose();
                    }
                }
            }
        }
    }
}
