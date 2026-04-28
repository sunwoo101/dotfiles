// VolumeContent — content-only (no PanelWindow). Hosted inside the
// shared Popouts wrapper. Owns sizing via contentWidth/contentHeight so
// the wrapper can morph to fit it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

Item {
    id: root

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    readonly property int contentWidth:  300
    readonly property int contentHeight: column.implicitHeight + 28
    readonly property int padding: 14

    implicitWidth:  contentWidth
    implicitHeight: contentHeight

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    readonly property var player: {
        var ps = Mpris.players.values;
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].trackTitle || ps[i].trackArtist) return ps[i];
        }
        return ps.length > 0 ? ps[0] : null;
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 10

        ClippingRectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth:  200
            Layout.preferredHeight: 200
            radius: 12
            color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)

            Image {
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                text: "♪"
                color: root.cMuted
                font.pixelSize: 64
                font.family: root.fontFamily
                visible: !root.player
                    || !root.player.trackArtUrl
                    || root.player.trackArtUrl === ""
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.player ? (root.player.trackTitle || "—") : "Nothing playing"
            color: root.cFg
            font.family: root.fontFamily
            font.pixelSize: 15
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            visible: !!root.player && (root.player.trackArtist || "") !== ""
            text: root.player ? (root.player.trackArtist || "") : ""
            color: root.cMuted
            font.family: root.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            CardButton {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 32
                cFg: root.cFg
                cPrimary: root.cPrimary
                enabled: !!root.player && root.player.canGoPrevious
                opacity: enabled ? 1 : 0.4
                onClicked: if (root.player) root.player.previous()
                TintedIcon {
                    anchors.centerIn: parent
                    name: "media-skip-backward-symbolic"
                    tint: root.cFg
                    size: 16
                }
            }
            CardButton {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 32
                cFg: root.cFg
                cPrimary: root.cPrimary
                enabled: !!root.player && root.player.canTogglePlaying
                opacity: enabled ? 1 : 0.4
                onClicked: if (root.player) root.player.togglePlaying()
                TintedIcon {
                    anchors.centerIn: parent
                    name: (root.player && root.player.isPlaying)
                        ? "media-playback-pause-symbolic"
                        : "media-playback-start-symbolic"
                    tint: root.cFg
                    size: 16
                }
            }
            CardButton {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 32
                cFg: root.cFg
                cPrimary: root.cPrimary
                enabled: !!root.player && root.player.canGoNext
                opacity: enabled ? 1 : 0.4
                onClicked: if (root.player) root.player.next()
                TintedIcon {
                    anchors.centerIn: parent
                    name: "media-skip-forward-symbolic"
                    tint: root.cFg
                    size: 16
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            CardButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                cFg: root.cFg
                cPrimary: root.cPrimary
                active: root.sink && root.sink.audio && root.sink.audio.muted
                onClicked: {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.muted = !root.sink.audio.muted;
                }
                TintedIcon {
                    anchors.centerIn: parent
                    name: (root.sink && root.sink.audio && root.sink.audio.muted)
                        ? "audio-volume-muted-symbolic"
                        : "audio-volume-high-symbolic"
                    tint: root.cFg
                    size: 18
                }
            }

            Item {
                id: slider
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                readonly property real fillFraction:
                    Math.max(0, Math.min(1, (root.sink && root.sink.audio) ? root.sink.audio.volume : 0))

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)

                    Rectangle {
                        width: parent.width * slider.fillFraction
                        height: parent.height
                        radius: parent.radius
                        color: root.cPrimary
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setFromX(x) {
                        if (!root.sink || !root.sink.audio) return;
                        root.sink.audio.volume = Math.max(0, Math.min(1, x / width));
                    }
                    onPressed: (m) => setFromX(m.x)
                    onPositionChanged: (m) => { if (pressed) setFromX(m.x); }
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: (root.sink && root.sink.audio)
                    ? Math.round(root.sink.audio.volume * 100) + "%"
                    : ""
                color: root.cFg
                font.family: root.fontFamily
                font.pixelSize: 13
            }
        }
    }
}
