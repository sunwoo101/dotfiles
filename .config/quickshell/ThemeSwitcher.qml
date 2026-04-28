// ThemeSwitcher — bottom hover-reveal panel. Bottom+center aligned: inverse
// bottom-LEFT and bottom-RIGHT (carve into the screen edge); rounded top-LEFT
// and top-RIGHT. When closed, peeks as an 8px sliver. Hover-driven open
// with a grace timer to absorb transient leave events Wayland sends while
// the surface is resizing during the animation.

import QtQuick
import Quickshell

Modal {
    id: themeSwitcher

    edge:  "bottom"
    align: "center"
    contentWidth: 560
    cornerRadius: 14

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property var mochaAccents
    required property string currentFlavor
    required property var setAccent
    required property var toggleFlavor
    required property var clearOverride

    readonly property int collapsedHeight: 8
    readonly property int expandedHeight:  260

    // always rendered (peek strip when not hovered) — drive height from a
    // separate hover state instead of Modal's open/closed binary.
    open: true
    property bool hovered: false
    contentHeight: hovered ? expandedHeight : collapsedHeight
    // Keep the Wayland layer surface a constant size so it doesn't get
    // re-configured on every hover toggle. Only the inner panel animates
    // 8 ↔ 260; the surface stays at expandedHeight always. Without this,
    // the compositor's surface-resize cycle showed a ghost "bar with
    // inverse rounds" that lagged behind the visible panel during close.
    surfaceHeight: expandedHeight

    // Hover-source counter — accepts events from both Modal's own root
    // HoverHandler (for cursor on the visible panel) and the external
    // bumper window (for cursor at the screen-edge deadzone). Mirrors the
    // _hoverDepth pattern in shell.qml: the close timer only restarts when
    // every source has reported leave, so handoff between sources doesn't
    // momentarily drop hovered=false.
    property int _hoverSources: 0

    // Driven by ThemeSwitcherBumper through shellRoot; setting this to true
    // emits a synthetic panelEnter so the same handlers fire as for cursor
    // hover on the panel itself.
    property bool externalHovered: false
    onExternalHoveredChanged: externalHovered ? panelEnter() : panelLeave()

    onPanelEnter: {
        _hoverSources += 1;
        closeTimer.stop();
        hovered = true;
    }
    onPanelLeave: {
        _hoverSources = Math.max(0, _hoverSources - 1);
        if (_hoverSources === 0) closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: themeSwitcher.hovered = false
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 14
        spacing: 14
        opacity: Math.max(0,
            (themeSwitcher.visibleHeight - themeSwitcher.collapsedHeight)
            / (themeSwitcher.expandedHeight - themeSwitcher.collapsedHeight))

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Theme Switcher"
            color: themeSwitcher.cFg
            font.pixelSize: 17
            font.family: themeSwitcher.fontFamily
            font.bold: true
        }

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: themeSwitcher.mochaAccents

                Rectangle {
                    required property var modelData
                    readonly property bool active: themeSwitcher.cPrimary == modelData.hex

                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 22
                    color: modelData.hex
                    scale: aMa.containsMouse ? 1.12 : 1.0
                    border.color: active ? themeSwitcher.cFg : "transparent"
                    border.width: active ? 3 : 0

                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                    Behavior on border.width { NumberAnimation { duration: 140 } }

                    MouseArea {
                        id: aMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeSwitcher.setAccent(parent.modelData.name, parent.modelData.hex)
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
                cFg: themeSwitcher.cFg
                cPrimary: themeSwitcher.cPrimary
                onClicked: themeSwitcher.toggleFlavor()

                TintedIcon {
                    anchors.centerIn: parent
                    name: themeSwitcher.currentFlavor === "mocha"
                        ? "weather-clear-night-symbolic"
                        : "weather-clear-symbolic"
                    tint: themeSwitcher.cFg
                    size: 20
                }
            }

            CardButton {
                implicitWidth: 120
                implicitHeight: 38
                cFg: themeSwitcher.cFg
                cPrimary: themeSwitcher.cPrimary
                onClicked: themeSwitcher.clearOverride()

                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: themeSwitcher.cFg
                    font.pixelSize: 14
                    font.family: themeSwitcher.fontFamily
                }
            }
        }
    }
}
