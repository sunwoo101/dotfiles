//@ pragma UseQApplication

// shell.qml — entry point. Holds shared state (colors, theme, system polling)
// and instantiates one Bar + one ThemeSwitcher per monitor via Variants.
// All visible chrome lives in Bar.qml / ThemeSwitcher.qml.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

ShellRoot {
    id: shellRoot

    // -- two-layer color system: base (colors.json) + override (cache) ----
    property string baseContents: ""
    property string overrideContents: ""

    FileView {
        id: baseFile
        path: Quickshell.env("HOME") + "/.config/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: shellRoot.baseContents = text()
    }
    FileView {
        id: overrideFile
        path: Quickshell.env("HOME") + "/.cache/quickshell/colors-override.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: shellRoot.overrideContents = text()
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

    // -- theme state + apply pipeline ------------------------------------
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

    property string currentAccent:    "mauve"
    property string currentAccentHex: "#cba6f7"
    property string currentFlavor:    "mocha"   // "mocha" | "latte"

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

    // -- system module polling -------------------------------------------
    property string volumeText: "??"
    property string batteryText: ""
    property bool   btConnected: false

    Timer {
        interval: 2000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            pollVolume.running = true;
            pollBattery.running = true;
            pollBluetooth.running = true;
        }
    }

    Process {
        id: pollVolume
        running: false
        command: ["sh", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | " +
            "awk '{ if($NF==\"[MUTED]\") print \"muted\"; else printf \"%d%%\", $2*100 }'"]
        stdout: StdioCollector { onStreamFinished: shellRoot.volumeText = text.trim() || "??" }
    }
    Process {
        id: pollBattery
        running: false
        command: ["sh", "-c",
            "p=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
            "s=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
            "[ -n \"$p\" ] && printf '%s%%%s' \"$p\" \"$([ \"$s\" = Charging ] && echo ' ⚡')\" || echo ''"]
        stdout: StdioCollector { onStreamFinished: shellRoot.batteryText = text.trim() }
    }
    Process {
        id: pollBluetooth
        running: false
        command: ["sh", "-c", "bluetoothctl info 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: shellRoot.btConnected = text.includes("Device") }
    }

    // -- notification center hover state ---------------------------------
    // shared by the Bar's bell + Notifications panel so hover-from-bell-to-panel
    // doesn't immediately close. Close-timer gives a 250ms grace period.
    property bool notifOpen: false
    Timer {
        id: notifCloseTimer
        interval: 250
        onTriggered: shellRoot.notifOpen = false
    }
    function notifEnter() { notifCloseTimer.stop(); notifOpen = true; }
    function notifLeave() { notifCloseTimer.restart(); }

    // -- notification daemon ---------------------------------------------
    // registers as the freedesktop notification server (replaces swaync). new
    // notifications are tracked (so the center can render them) AND pushed to
    // `popped` for ~5s so the panel auto-pops in compact form.
    property var popped: []
    function popNotif(n) {
        popped = [...popped, n];
        popTimerComp.createObject(shellRoot, { notif: n });
    }
    function expirePopped(n) { popped = popped.filter(x => x !== n); }

    Component {
        id: popTimerComp
        Timer {
            property var notif
            interval: 5000
            running: true
            repeat: false
            onTriggered: {
                shellRoot.expirePopped(notif);
                destroy();
            }
        }
    }

    NotificationServer {
        id: notifSrv
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;
            shellRoot.popNotif(n);
        }
    }

    // -- per-monitor instances -------------------------------------------
    Variants {
        model: Quickshell.screens
        Bar {
            modelData: modelData
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            volumeText: shellRoot.volumeText
            batteryText: shellRoot.batteryText
            btConnected: shellRoot.btConnected
            notifCount: notifSrv.trackedNotifications.values.length
            onBellEnter:  shellRoot.notifEnter()
            onBellLeave:  shellRoot.notifLeave()
        }
    }

    Variants {
        model: Quickshell.screens
        ThemeSwitcher {
            modelData: modelData
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            mochaAccents: shellRoot.mochaAccents
            currentFlavor: shellRoot.currentFlavor
            setAccent: (name, hex) => shellRoot.setAccent(name, hex)
            toggleFlavor: () => shellRoot.toggleFlavor()
            clearOverride: () => shellRoot.clearOverride()
        }
    }

    Variants {
        model: Quickshell.screens
        Notifications {
            modelData: modelData
            notifServer: notifSrv
            popped: shellRoot.popped
            expireCallback: (n) => shellRoot.expirePopped(n)
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            open: shellRoot.notifOpen
            onPanelEnter: shellRoot.notifEnter()
            onPanelLeave: shellRoot.notifLeave()
        }
    }
}
