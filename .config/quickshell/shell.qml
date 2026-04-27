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
            "~/dotfiles/scripts/render_configs.sh && ~/dotfiles/scripts/reload_all.sh"
        ]
    }
    function setPrimary(hex) {
        writeOverride.running = false;
        writeOverride.command = [
            "python3", "-c",
            "import json,sys,pathlib;p=pathlib.Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True);d=json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {};d.setdefault('ui',{})['primary']=sys.argv[2];p.write_text(json.dumps(d,indent=2)+'\\n')",
            Quickshell.env("HOME") + "/.cache/quickshell/colors-override.json",
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

                // TEST: primary-color picker --------------------------------
                // writes to ~/.cache/quickshell/colors-override.json (gitignored)
                // not to colors.json — repo stays clean. R = clear override.
                RowLayout {
                    spacing: 4

                    Repeater {
                        model: [
                            { hex: "#cba6f7", label: "M" },  // mauve
                            { hex: "#f5c2e7", label: "P" },  // pink
                            { hex: "#89b4fa", label: "B" },  // blue
                            { hex: "#a6e3a1", label: "G" },  // green
                            { hex: "#f9e2af", label: "Y" }   // yellow
                        ]

                        Rectangle {
                            required property var modelData
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 4
                            color: modelData.hex

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: cBg
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "JetBrainsMono Nerd Font"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: setPrimary(parent.modelData.hex)
                            }
                        }
                    }

                    // reset button
                    Rectangle {
                        implicitWidth: 20
                        implicitHeight: 20
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
