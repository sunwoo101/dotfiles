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
    function setAccent(name, hex) {
        writeOverride.running = false;
        writeOverride.command = [
            "python3", "-c",
            "import json,sys,pathlib\n" +
            "p=pathlib.Path(sys.argv[1])\n" +
            "p.parent.mkdir(parents=True,exist_ok=True)\n" +
            "gtk,cursor,primary=sys.argv[2],sys.argv[3],sys.argv[4]\n" +
            "r,g,b=int(primary[1:3],16),int(primary[3:5],16),int(primary[5:7],16)\n" +
            "tint=lambda f:f'#{int(r*f):02x}{int(g*f):02x}{int(b*f):02x}'\n" +
            "d=json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {}\n" +
            "d.setdefault('theme',{}).update({'gtk':gtk,'cursor':cursor})\n" +
            "d.setdefault('ui',{}).update({\n" +
            "  'primary':primary,'accent':primary,'url':primary,\n" +
            "  'bg':tint(0.13),'mantle':tint(0.10),\n" +
            "  'muted':tint(0.40),'border':tint(0.28)\n" +
            "})\n" +
            "p.write_text(json.dumps(d,indent=2)+'\\n')",
            Quickshell.env("HOME") + "/.cache/quickshell/colors-override.json",
            "catppuccin-mocha-" + name + "-standard+default",
            "catppuccin-mocha-" + name + "-cursors",
            hex
        ];
        writeOverride.running = true;
    }
    function clearOverride() {
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
                Text {
                    text: "  " + volumeText
                    color: cFg
                    font.pixelSize: 12
                    font.family: fontFamily
                }

                // bluetooth — only show when connected
                Text {
                    text: ""
                    color: cFg
                    font.pixelSize: 12
                    font.family: fontFamily
                    visible: btConnected
                }

                // battery — only show if a battery exists
                Text {
                    text: "  " + batteryText
                    color: cFg
                    font.pixelSize: 12
                    font.family: fontFamily
                    visible: batteryText !== ""
                }

                // separator
                Rectangle {
                    implicitWidth: 1
                    implicitHeight: 16
                    color: cMuted
                    visible: true
                }

                // accent picker (TEST)
                RowLayout {
                    spacing: 3

                    Repeater {
                        model: mochaAccents

                        Rectangle {
                            required property var modelData
                            readonly property bool active: cPrimary == modelData.hex

                            implicitWidth: 14
                            implicitHeight: 14
                            radius: 7
                            color: modelData.hex
                            border.color: active ? cFg : "transparent"
                            border.width: active ? 2 : 0

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: setAccent(parent.modelData.name, parent.modelData.hex)
                            }
                        }
                    }

                    Item { implicitWidth: 4 }

                    Rectangle {
                        implicitWidth: 16
                        implicitHeight: 16
                        radius: 4
                        color: "transparent"
                        border.color: cMuted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "R"
                            color: cFg
                            font.pixelSize: 9
                            font.bold: true
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
