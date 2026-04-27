//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    // -- two-layer color system ----------------------------------------
    property string baseContents: ""
    property string overrideContents: ""

    FileView {
        id: baseFile
        path: Quickshell.env("HOME") + "/.config/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: baseContents = text()
    }
    FileView {
        id: overrideFile
        path: Quickshell.env("HOME") + "/.cache/quickshell/colors-override.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: overrideContents = text()
    }

    Process {
        id: initOverride
        running: true
        command: [
            "sh", "-c",
            "mkdir -p ~/.cache/quickshell && [ -f ~/.cache/quickshell/colors-override.json ] || echo '{}' > ~/.cache/quickshell/colors-override.json"
        ]
        onExited: overrideFile.reload()
    }

    function safeParse(text) {
        if (!text) return null;
        try { return JSON.parse(text); } catch (e) { return null; }
    }

    property var colors: {
        var base = safeParse(baseContents);
        var over = safeParse(overrideContents);
        if (!base) return null;
        if (!over) return base;
        var merged = JSON.parse(JSON.stringify(base));
        for (var section in over) {
            if (typeof over[section] === "object" && merged[section]) {
                for (var key in over[section]) merged[section][key] = over[section][key];
            } else {
                merged[section] = over[section];
            }
        }
        return merged;
    }

    property color cBg:      colors ? colors.ui.bg      : "#1e1e2e"
    property color cFg:      colors ? colors.ui.fg      : "#cdd6f4"
    property color cPrimary: colors ? colors.ui.primary : "#cba6f7"
    property color cAccent:  colors ? colors.ui.accent  : "#f5c2e7"
    property color cMuted:   colors ? colors.ui.muted   : "#6c7086"
    property real  cAlpha:   colors ? colors.opacity.bg : 0.7
    property string fontFamily: "JetBrainsMono Nerd Font"

    // -- accent picker (TEST) -------------------------------------------
    Process {
        id: writeOverride
        running: false
        onExited: (code, status) => {
            overrideFile.reload();
            applyChain.running = true;
        }
    }
    Process {
        id: applyChain
        running: false
        command: [
            "sh", "-c",
            "~/dotfiles/scripts/render_configs.sh && ~/dotfiles/scripts/apply_gsettings.sh && ~/dotfiles/scripts/reload_all.sh"
        ]
    }
    // currentAccent + currentFlavor — used by setAccent / toggleFlavor so each
    // can re-apply the other's last value when invoked.
    property string currentAccent:    "mauve"
    property string currentAccentHex: "#cba6f7"
    property string currentFlavor:    "mocha"   // "mocha" or "latte"

    // setAccent rebuilds the whole UI palette via apply_palette.py.
    // Writes theme.{gtk,cursor}, ui.* (palette-tinted), ansi.* (flavor-specific).
    function setAccent(name, hex) {
        currentAccent = name;
        currentAccentHex = hex;
        applyPalette();
    }
    function toggleFlavor() {
        currentFlavor = currentFlavor === "mocha" ? "latte" : "mocha";
        applyPalette();
    }
    function applyPalette() {
        writeOverride.running = false;
        writeOverride.command = [
            "python3",
            Quickshell.env("HOME") + "/dotfiles/scripts/apply_palette.py",
            currentFlavor,
            currentAccent,
            currentAccentHex
        ];
        writeOverride.running = true;
    }
    function clearOverride() {
        // also reset state so subsequent accent clicks don't carry the
        // previous flavor (e.g. stuck in Latte after reset).
        currentFlavor = "mocha";
        currentAccent = "mauve";
        currentAccentHex = "#cba6f7";
        writeOverride.running = false;
        writeOverride.command = [
            "sh", "-c",
            "echo '{}' > ~/.cache/quickshell/colors-override.json"
        ];
        writeOverride.running = true;
    }

    property var mochaAccents: [
        { name: "rosewater", hex: "#f5e0dc" },
        { name: "flamingo",  hex: "#f2cdcd" },
        { name: "pink",      hex: "#f5c2e7" },
        { name: "mauve",     hex: "#cba6f7" },
        { name: "red",       hex: "#f38ba8" },
        { name: "maroon",    hex: "#eba0ac" },
        { name: "peach",     hex: "#fab387" },
        { name: "yellow",    hex: "#f9e2af" },
        { name: "green",     hex: "#a6e3a1" },
        { name: "teal",      hex: "#94e2d5" },
        { name: "sky",       hex: "#89dceb" },
        { name: "sapphire",  hex: "#74c7ec" },
        { name: "blue",      hex: "#89b4fa" },
        { name: "lavender",  hex: "#b4befe" }
    ]

    // -- system module polling -----------------------------------------
    // simple Process-based polling — reliable across Quickshell versions and
    // works regardless of audio backend (pipewire/pulseaudio).
    property string volumeText: "??"
    property string batteryText: ""
    property bool   btConnected: false

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pollVolume.running = true
            pollBattery.running = true
            pollBluetooth.running = true
        }
    }

    Process {
        id: pollVolume
        running: false
        command: ["sh", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | " +
            "awk '{ if($NF==\"[MUTED]\") print \"muted\"; else printf \"%d%%\", $2*100 }'"]
        stdout: StdioCollector { onStreamFinished: volumeText = text.trim() || "??" }
    }

    Process {
        id: pollBattery
        running: false
        command: ["sh", "-c",
            "p=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
            "s=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
            "[ -n \"$p\" ] && printf '%s%%%s' \"$p\" \"$([ \"$s\" = Charging ] && echo ' ⚡')\" || echo ''"]
        stdout: StdioCollector { onStreamFinished: batteryText = text.trim() }
    }

    Process {
        id: pollBluetooth
        running: false
        command: ["sh", "-c", "bluetoothctl info 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: btConnected = text.includes("Device") }
    }

    // -- bar (one per monitor) -----------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            readonly property int  barHeight:  38
            readonly property int  cornerSize: 16  // gaps_out (8) + window rounding (8)
            readonly property color barColor:  cBg   // dev: opaque (use Qt.rgba(cBg.r,cBg.g,cBg.b,cAlpha) for translucent)

            anchors { top: true; left: true; right: true }
            implicitHeight: barHeight + cornerSize
            exclusiveZone: barHeight   // only reserve the bar itself, corners overhang
            color: "transparent"

            // bar background (top portion)
            Rectangle {
                id: barBg
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: bar.barHeight
                color: bar.barColor
            }

            // inverse-rounded LEFT corner — extends bar's color past its bottom
            // edge then curves outward, leaving a window-shaped notch
            Shape {
                width: bar.cornerSize
                height: bar.cornerSize
                anchors {
                    left: parent.left
                    top: parent.top
                    topMargin: bar.barHeight
                }
                ShapePath {
                    strokeWidth: 0
                    fillColor: bar.barColor
                    startX: 0
                    startY: 0
                    PathLine { x: bar.cornerSize; y: 0 }
                    PathArc {
                        x: 0; y: bar.cornerSize
                        radiusX: bar.cornerSize
                        radiusY: bar.cornerSize
                        direction: PathArc.Counterclockwise
                    }
                    PathLine { x: 0; y: 0 }
                }
            }

            // inverse-rounded RIGHT corner — mirror of left
            Shape {
                width: bar.cornerSize
                height: bar.cornerSize
                anchors {
                    right: parent.right
                    top: parent.top
                    topMargin: bar.barHeight
                }
                ShapePath {
                    strokeWidth: 0
                    fillColor: bar.barColor
                    startX: 0
                    startY: 0
                    PathLine { x: bar.cornerSize; y: 0 }
                    PathLine { x: bar.cornerSize; y: bar.cornerSize }
                    PathArc {
                        x: 0; y: 0
                        radiusX: bar.cornerSize
                        radiusY: bar.cornerSize
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            // LEFT — clock + window title
            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: barBg.verticalCenter
                anchors.leftMargin: 12
                spacing: 14

                Text {
                    id: clock
                    color: cPrimary
                    font.pixelSize: 13
                    font.family: fontFamily
                    font.bold: true

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: clock.text =
                            Qt.formatDateTime(new Date(), "HH:mm  ddd dd MMM")
                    }
                }

                Text {
                    text: Hyprland.focusedClient ? Hyprland.focusedClient.title : ""
                    color: cMuted
                    font.pixelSize: 12
                    font.family: fontFamily
                    elide: Text.ElideRight
                    Layout.maximumWidth: 320
                }
            }

            // CENTER — workspaces
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: barBg.verticalCenter
                spacing: 4

                Repeater {
                    model: 10

                    Rectangle {
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool active:
                            Hyprland.focusedWorkspace
                            && Hyprland.focusedWorkspace.id === wsId

                        implicitWidth: 22
                        implicitHeight: 20
                        radius: 4
                        color: active ? cPrimary : "transparent"
                        border.color: cMuted
                        border.width: active ? 0 : 1

                        Text {
                            anchors.centerIn: parent
                            text: parent.wsId
                            color: parent.active ? cBg : cFg
                            font.pixelSize: 12
                            font.family: fontFamily
                            font.bold: true
                            Component.onCompleted: console.log("workspace ws#" + parent.wsId + " resolved font:", font.family)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                        }
                    }
                }
            }

            // RIGHT — system modules + accent picker
            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: barBg.verticalCenter
                anchors.rightMargin: 12
                spacing: 14

                // volume
                Row {
                    spacing: 4
                    TintedIcon {
                        name: volumeText === "muted" ? "audio-volume-muted-symbolic"
                            : "audio-volume-high-symbolic"
                        tint: cFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: volumeText
                        color: cFg
                        font.pixelSize: 12
                        font.family: fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // bluetooth — only show when connected
                TintedIcon {
                    name: "bluetooth-active-symbolic"
                    tint: cFg
                    visible: btConnected
                }

                // battery — only show if a battery exists
                Row {
                    spacing: 4
                    visible: batteryText !== ""
                    TintedIcon {
                        name: "battery-good-symbolic"
                        tint: cFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: batteryText
                        color: cFg
                        font.pixelSize: 12
                        font.family: fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

            }
        }
    }

    // -- bottom theme switcher panel (hover to reveal) -------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: themeSwitcher
            required property var modelData
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

                // safe top radius: shrinks when panel is small (collapsed) so the
                // peeking strip looks like a small pill, not a broken oversized arc.
                readonly property real safeTopRadius:
                    Math.min(themeSwitcher.topRadius, panel.height / 2)

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: themeSwitcher.open = true
                    onExited:  themeSwitcher.open = false
                }

                // main panel body — rounded top, sharp bottom. always visible.
                Shape {
                    anchors.fill: parent

                    ShapePath {
                        strokeWidth: 0
                        fillColor: cBg

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

                // bottom-LEFT inverse corner — fades in only when expanded
                Shape {
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                    }
                    width: themeSwitcher.invRadius
                    height: themeSwitcher.invRadius
                    opacity: panel.height > themeSwitcher.invRadius * 2 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    ShapePath {
                        strokeWidth: 0
                        fillColor: cBg
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

                // bottom-RIGHT inverse corner — mirror of left
                Shape {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                    }
                    width: themeSwitcher.invRadius
                    height: themeSwitcher.invRadius
                    opacity: panel.height > themeSwitcher.invRadius * 2 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    ShapePath {
                        strokeWidth: 0
                        fillColor: cBg
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

                // content: title + 14-color grid + reset
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
                        color: cFg
                        font.pixelSize: 14
                        font.family: fontFamily
                        font.bold: true
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 7
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: mochaAccents

                            Rectangle {
                                required property var modelData
                                readonly property bool active: cPrimary == modelData.hex

                                implicitWidth: 36
                                implicitHeight: 36
                                radius: 18
                                color: modelData.hex
                                border.color: active ? cFg : "transparent"
                                border.width: active ? 3 : 0

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: setAccent(parent.modelData.name, parent.modelData.hex)
                                }
                            }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        // dark/light toggle — sun/moon glyphs
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 28
                            radius: 6
                            color: "transparent"
                            border.color: cMuted
                            border.width: 1

                            TintedIcon {
                                anchors.centerIn: parent
                                name: currentFlavor === "mocha"
                                    ? "weather-clear-night-symbolic"
                                    : "weather-clear-symbolic"
                                tint: cFg
                                size: 16


                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toggleFlavor()
                            }
                        }

                        // reset
                        Rectangle {
                            implicitWidth: 90
                            implicitHeight: 28
                            radius: 6
                            color: "transparent"
                            border.color: cMuted
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Reset"
                                color: cFg
                                font.pixelSize: 12
                                font.family: fontFamily
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clearOverride()
                            }
                        }
                    }
                }
            }
        }
    }
}
