// Bar — top bar PanelWindow per monitor.
// Receives all colors + system module state via properties from shell.qml so it
// can be moved/instantiated independently.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

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
    required property bool   notifMuted
    required property bool   notifOpen
    required property bool   powerOpen
    required property bool   volumeOpen
    required property bool   calendarOpen
    required property string osId
    required property bool   launcherOpen
    required property bool   workspacesOpen

    // Hover signals — Bar fires both with the name of whichever icon's
    // MouseArea fired (e.g. "volume", "workspaces", "launcher", "tray:0").
    // shell.qml dispatches by name into the popout system (left/right
    // tray/etc.) or the center system (launcher / workspaces overview).
    signal popoutEnter(string name)
    signal popoutLeave(string name)
    // Click on the bell icon — shellRoot toggles `notifMuted`. Hover still
    // opens the notifications popout.
    signal notifMuteToggle()

    // OS-logo glyph from Nerd Fonts' Linux distro icon set (codepoints
    // U+F300–U+F33F). The shell already uses JetBrainsMono Nerd Font, so
    // these glyphs render natively as a Text element — tintable via color
    // and consistent stroke weight with the rest of the bar.
    // Fallback to the generic Linux/Tux glyph (FontAwesome U+F17C) for
    // distros not in this map.
    readonly property string osLogoGlyph: {
        switch (osId) {
            case "arch":
            case "archlinux":   return "";
            case "ubuntu":      return "";
            case "fedora":      return "";
            case "debian":      return "";
            case "manjaro":     return "";
            case "nixos":       return "";
            case "pop":
            case "pop_os":
            case "popos":       return "";
            case "linuxmint":   return "";
            case "gentoo":      return "";
            case "alpine":      return "";
            case "kali":        return "";
            case "opensuse":
            case "opensuse-tumbleweed":
            case "opensuse-leap": return "";
            case "void":        return "";
            case "endeavouros": return "";
            case "raspbian":    return "";
            case "elementary":  return "";
            default:            return "";   // generic Tux
        }
    }

    // Screen-relative anchor X positions, used by Popouts.qml.
    // Right-side popouts pin their right edge here:
    readonly property real volumeRightX:
        rightSection.x + rightRow.x + volWrap.x + volWrap.width
    readonly property real bellRightX:
        rightSection.x + rightRow.x + bellWrap.x + bellWrap.width
    // Updated imperatively by the tray icon delegate's onEntered: the
    // right-edge X (in bar root coords) of whichever tray icon is hovered.
    // Different popout names ("tray:0", "tray:1", ...) trigger the wrapper's
    // morph; this anchor gives each its own resting position.
    property real trayItemRightX: 0
    // Left-side popouts pin their left edge here:
    readonly property real clockLeftX:
        leftSection.x + clock.x
    readonly property real powerLeftX: 0   // power menu hangs from screen left
    // Center-anchor for the workspaces overview popout (cluster's center X).
    readonly property real workspacesCenterX:
        wsCluster.x + wsCluster.width / 2

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
                onExited:  bar.popoutLeave("power")
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
                onExited:  bar.popoutLeave("calendar")
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

    // CENTER — launcher logo + workspace pills, sharing a centered Row
    // but each segment owns its own hover MouseArea so they trigger
    // independent popouts. No wrapping hover handler — that would open
    // the workspaces overview when hovering the launcher.
    Item {
        id: wsCluster
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: barBg.verticalCenter
        implicitWidth:  centerRow.implicitWidth
        implicitHeight: centerRow.implicitHeight

        Row {
            id: centerRow
            anchors.fill: parent
            spacing: 8

            // Launcher icon — hover opens the app launcher (matches every
            // other bar icon's hover-to-open behavior).
            Item {
                id: launcherBtn
                width:  26
                height: 26
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: bar.osLogoGlyph
                    font.family: bar.fontFamily
                    font.pixelSize: 20
                    color: (launcherMa.containsMouse || bar.launcherOpen)
                        ? bar.cPrimary : bar.cFg
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: launcherMa
                    anchors.fill: parent
                    anchors.topMargin: -(bar.barHeight - 26) / 2
                    anchors.bottomMargin: -(bar.barHeight - 26) / 2
                    anchors.leftMargin: -6
                    anchors.rightMargin: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: bar.popoutEnter("launcher")
                    onExited:  bar.popoutLeave("launcher")
                }
            }

            // Workspace pills — own hover MouseArea opens the workspaces
            // overview popout. Pills are non-interactive visual indicators.
            Item {
                id: wsArea
                width:  wsRow.implicitWidth
                height: wsRow.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                RowLayout {
                    id: wsRow
                    anchors.fill: parent
                    spacing: 6

                    Repeater {
                        // Hyprland.workspaces.values is the list of workspaces
                        // that exist — i.e. ones with windows OR the active one.
                        model: Hyprland.workspaces.values

                        Rectangle {
                            id: wsPill
                            required property var modelData
                            readonly property int wsId: modelData.id
                            readonly property bool active: Hyprland.focusedWorkspace
                                && Hyprland.focusedWorkspace.id === wsId

                            Layout.preferredWidth: active ? 44 : 22
                            Layout.preferredHeight: 22
                            radius: height / 2
                            color: active
                                ? Qt.rgba(bar.cFg.r, bar.cFg.g, bar.cFg.b, 0.18)
                                : Qt.rgba(bar.cFg.r, bar.cFg.g, bar.cFg.b, 0.06)
                            border.color: active
                                ? bar.cPrimary
                                : Qt.rgba(bar.cFg.r, bar.cFg.g, bar.cFg.b, 0.10)
                            border.width: 1

                            Behavior on Layout.preferredWidth {
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            Behavior on color        { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: wsPill.wsId
                                color: bar.cFg
                                opacity: wsPill.active ? 1 : 0.2
                                font.pixelSize: 15
                                font.family: bar.fontFamily
                                font.bold: true
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -(bar.barHeight - wsRow.implicitHeight) / 2
                    anchors.bottomMargin: -(bar.barHeight - wsRow.implicitHeight) / 2
                    anchors.leftMargin: -6
                    anchors.rightMargin: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: bar.popoutEnter("workspaces")
                    onExited:  bar.popoutLeave("workspaces")
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

        // system tray (StatusNotifierItem) — left-most cluster on the
        // right side. Left-click activates (or shows menu for menu-only
        // items); right-click shows the tray menu via QsMenuAnchor.
        Row {
            id: trayRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            visible: SystemTray.items.values.length > 0

            Repeater {
                // Filter out Passive items per the SNI spec: hosts should
                // only display Active or NeedsAttention. NeedsAttention
                // items get a small accent dot rendered below.
                model: SystemTray.items.values.filter(i => i.status !== Status.Passive)

                Item {
                    id: trayItem
                    required property var modelData
                    required property int index
                    readonly property int iconSize: 20
                    readonly property bool needsAttention:
                        modelData.status === Status.NeedsAttention
                    implicitWidth:  iconSize
                    implicitHeight: iconSize
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: trayItem.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        sourceSize.width:  trayItem.iconSize * 2
                        sourceSize.height: trayItem.iconSize * 2
                        opacity: trayMa.containsMouse ? 1.0 : 0.85
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    // NeedsAttention dot — small cPrimary pulse below the
                    // icon. SNI defines this status for "the user should
                    // look at this" (e.g. unread chat).
                    Rectangle {
                        visible: trayItem.needsAttention
                        width: 6; height: 6; radius: 3
                        color: bar.cPrimary
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -3
                        SequentialAnimation on opacity {
                            running: trayItem.needsAttention
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }

                    MouseArea {
                        id: trayMa
                        anchors.fill: parent
                        anchors.topMargin: -(bar.barHeight - trayItem.iconSize) / 2
                        anchors.bottomMargin: -(bar.barHeight - trayItem.iconSize) / 2
                        anchors.leftMargin: -4
                        anchors.rightMargin: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onEntered: {
                            // Capture this icon's right-edge X in bar root
                            // coords. mapToItem(bar, …) doesn't work — `bar`
                            // is a PanelWindow (Window), not a QQuickItem.
                            // Sum the ancestor positions directly, same
                            // pattern as volumeRightX/bellRightX above.
                            bar.trayItemRightX =
                                rightSection.x + rightRow.x + trayRow.x
                                + trayItem.x + trayItem.width;
                            bar.popoutEnter("tray:" + trayItem.index);
                        }
                        onExited: bar.popoutLeave("tray:" + trayItem.index)
                        onClicked: (mouse) => {
                            var item = trayItem.modelData;
                            if (mouse.button === Qt.MiddleButton) {
                                item.secondaryActivate();
                            } else if (!item.onlyMenu) {
                                item.activate();
                            }
                        }
                        onWheel: (wheel) => {
                            trayItem.modelData.scroll(wheel.angleDelta.y, false);
                        }
                    }
                }
            }
        }

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
                cursorShape: Qt.PointingHandCursor
                onEntered: bar.popoutEnter("volume")
                onExited:  bar.popoutLeave("volume")
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
                    name: bar.notifMuted
                        ? "notifications-disabled-symbolic"
                        : (bar.notifCount > 0
                            ? "critical-notif-symbolic"
                            : "low-notif-symbolic")
                    tint: bar.notifMuted
                        ? bar.cMuted
                        : ((bellMa.containsMouse || bar.notifOpen)
                            ? bar.cPrimary : bar.cFg)
                    size: 20
                    Behavior on tint { ColorAnimation { duration: 120 } }
                }
                Text {
                    visible: bar.notifCount > 0
                    text: bar.notifCount
                    color: bar.notifMuted ? bar.cMuted : bar.cPrimary
                    font.pixelSize: 15
                    font.family: bar.fontFamily
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 120 } }
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
                cursorShape: Qt.PointingHandCursor
                onEntered: bar.popoutEnter("notifications")
                onExited:  bar.popoutLeave("notifications")
                onClicked: bar.notifMuteToggle()
            }
        }
    }
    }
}
