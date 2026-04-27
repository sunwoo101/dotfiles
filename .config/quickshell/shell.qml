//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    // -- two-layer color system ----------------------------------------
    // base: ~/.config/colors.json (in dotfiles repo, read-only at runtime)
    // override: ~/.cache/quickshell/colors-override.json (gitignored, mutable)
    // final colors = base shallow-merged with override.
    // text is a method on FileView, not a property — capture it into our own
    // observable string properties so QML bindings re-evaluate on change.
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

    // create the override file (empty {}) at startup so FileView can watch it
    // immediately and Process writes update an existing file (more reliable
    // than create-then-watch).
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

    // shallow merge: override.ui takes priority over base.ui, etc.
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

    // -- TEST: write override + render + reload -------------------------
    // chain: write override → run render_configs.sh (regenerates kitty.conf,
    // gtk.css etc. with merged colors) → run reload_all.sh (pushes live to
    // running kitty/hyprland).
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
    // setAccent rebuilds the whole UI palette from a single accent color.
    // changes: theme.gtk, theme.cursor, ui.{primary,accent,url,bg,mantle,muted,border}.
    // ANSI palette + ui.fg are left at base so terminal apps stay consistent
    // and text remains readable.
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

    // all 14 Catppuccin Mocha accent variants
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

    // -- bar (one per monitor) -------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: 32
            color: Qt.rgba(cBg.r, cBg.g, cBg.b, cAlpha)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 16

                // workspaces (1..10) ---------------------------------------
                RowLayout {
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
                                font.pixelSize: 11
                                font.family: "JetBrainsMono Nerd Font"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                            }
                        }
                    }
                }

                // active window title ------------------------------------
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: Hyprland.focusedClient
                        ? Hyprland.focusedClient.title
                        : ""
                    color: cMuted
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                }

                // TEST: Catppuccin Mocha accent picker ---------------------
                // 14 accent variants. each click writes theme.gtk +
                // theme.cursor + ui.primary to override (gitignored).
                // active accent gets a cFg border. R clears override.
                RowLayout {
                    spacing: 3

                    Repeater {
                        model: mochaAccents

                        Rectangle {
                            required property var modelData
                            readonly property bool active: cPrimary == modelData.hex

                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
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

                    // reset button
                    Rectangle {
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: 4
                        color: "transparent"
                        border.color: cMuted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "R"
                            color: cFg
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "JetBrainsMono Nerd Font"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clearOverride()
                        }
                    }
                }

                // current-primary swatch — always visible, shows live cPrimary
                Rectangle {
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: cPrimary
                    border.color: cMuted
                    border.width: 1
                }

                // clock — tinted with cPrimary so changes are obvious
                Text {
                    id: clock
                    color: cPrimary
                    font.pixelSize: 13
                    font.family: "JetBrainsMono Nerd Font"
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
            }
        }
    }
}
