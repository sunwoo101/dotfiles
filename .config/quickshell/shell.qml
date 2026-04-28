//@ pragma UseQApplication

// shell.qml — entry point. Holds shared state (colors, theme, system polling)
// and instantiates one Bar + one ThemeSwitcher per monitor via Variants.
// All visible chrome lives in Bar.qml / ThemeSwitcher.qml.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

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
        onLoaded: {
            shellRoot.overrideContents = text();
            shellRoot.overrideLoaded = true;
            shellRoot.maybeHydrate();
        }
    }

    // hydrate gating — both the override file must be loaded AND the root
    // component fully instantiated (so per-screen Bars/panels exist) before
    // we kick apply_palette. Otherwise the apply chain races component
    // construction and the bar paints once with stale fallback colors.
    property bool overrideLoaded: false
    property bool componentsReady: false
    property bool hydrated: false
    function maybeHydrate() {
        if (hydrated) return;
        if (!overrideLoaded || !componentsReady) return;
        hydrated = true;
        hydrateFromOverride();
    }
    Component.onCompleted: {
        componentsReady = true;
        maybeHydrate();
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

    property real  cAlpha:   colors ? colors.opacity.bg : 1.0
    property color cBg: {
        var c = Qt.color(colors ? colors.ui.bg : "#ff0000");
        return Qt.rgba(c.r, c.g, c.b, cAlpha);
    }
    property color cFg:      colors ? colors.ui.fg      : "#ff0000"
    property color cPrimary: colors ? colors.ui.primary : "#ff0000"
    property color cAccent:  colors ? colors.ui.accent  : "#ff0000"
    property color cMuted:   colors ? colors.ui.muted   : "#ff0000"
    property color cRed:     colors ? colors.ansi.red   : "#ff0000"
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
    // Flips to true after the first apply chain run completes. Used to gate
    // per-screen component instantiation so nothing paints with the launch
    // fallback color.
    property bool appliedReady: false
    Process {
        id: applyChain
        running: false
        command: [
            "sh", "-c",
            "~/dotfiles/scripts/render_configs.sh && ~/dotfiles/scripts/apply_gsettings.sh && ~/dotfiles/scripts/reload_all.sh"
        ]
        onExited: shellRoot.appliedReady = true
    }

    property string currentAccent:    "mauve"
    property string currentAccentHex: "#cba6f7"
    property string currentFlavor:    "mocha"   // "mocha" | "latte"

    // Rehydrate accent/flavor from the override file once on launch, then
    // re-run apply_palette.py so generated files (kitty/gtk/ohmyposh/etc.)
    // and live apps come back into sync with whatever the override says.
    // Without this, a fresh QS session has correct in-shell colors (FileView
    // merge) but stale generated files from the previous session.
    function hydrateFromOverride() {
        var over = safeParse(overrideContents);
        var gtk = over && over.theme ? over.theme.gtk : null;
        // theme.gtk looks like "catppuccin-{flavor}-{accent}-standard+default"
        var m = gtk ? /^catppuccin-(mocha|latte)-([a-z]+)-/.exec(gtk) : null;
        var flavor = m ? m[1] : currentFlavor;
        var accent = m ? m[2] : currentAccent;
        var hex    = over && over.ui && over.ui.primary
            ? over.ui.primary
            : currentAccentHex;
        applyTheme(flavor, accent, hex);
    }

    // Single entry point — every theme change (accent click, dark/light
    // toggle, launch hydrate) goes through this so the chain runs in exactly
    // one shape: state mutation → applyPalette → writeOverride → applyChain.
    function applyTheme(flavor, accent, hex) {
        currentFlavor    = flavor;
        currentAccent    = accent;
        currentAccentHex = hex;
        applyPalette();
    }
    function setAccent(name, hex) {
        applyTheme(currentFlavor, name, hex);
    }
    function toggleFlavor() {
        applyTheme(currentFlavor === "mocha" ? "latte" : "mocha",
                   currentAccent, currentAccentHex);
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
    // Volume is reactive via Pipewire service — no polling. Battery and
    // bluetooth still poll because we don't have reactive sources wired up.
    property string batteryText: ""
    property bool   btConnected: false

    readonly property var _sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: _sink ? [_sink] : [] }
    readonly property string volumeText: {
        if (!_sink || !_sink.audio) return "??";
        if (_sink.audio.muted) return "muted";
        return Math.round(_sink.audio.volume * 100) + "%";
    }

    Timer {
        interval: 2000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            pollBattery.running = true;
            pollBluetooth.running = true;
        }
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

    // -- unified bar-popout state ----------------------------------------
    // All top-bar drop-downs (volume, notifications, calendar, power)
    // share one Popouts wrapper that morphs between them. `popoutHover`
    // is what the user's currently hovering. `popoutCurrent` is what we
    // actually show — falls back to "notifications" if there are popped
    // notifs and nothing else is hovered, so they auto-pop without hover.
    // IPC can also force a name (e.g. `qs ipc call power toggle`).
    property string popoutHover: ""
    property string popoutForced: ""   // set by IPC; cleared on hover
    // Hover-source depth counter: each icon's onEntered / each panel
    // HoverHandler hovered=true increments; the corresponding leave
    // decrements. The close timer only restarts when depth hits 0.
    // Without this, event-ordering quirks (icon B's onEntered firing
    // before icon A's onExited) caused the popout to "open then
    // instantly close" while sweeping between adjacent triggers.
    property int _hoverDepth: 0
    Timer {
        id: popoutCloseTimer
        interval: 250
        onTriggered: { shellRoot.popoutHover = ""; shellRoot.popoutForced = ""; }
    }
    function popoutEnter(name) {
        _hoverDepth += 1;
        popoutCloseTimer.stop();
        popoutHover = name;
        popoutForced = "";   // hover overrides IPC
    }
    function popoutLeave() {
        _hoverDepth = Math.max(0, _hoverDepth - 1);
        if (_hoverDepth === 0) popoutCloseTimer.restart();
    }
    function popoutShow(name) {
        popoutCloseTimer.stop();
        popoutForced = name;
        popoutHover = "";
    }
    function popoutHide() {
        popoutForced = "";
        popoutHover = "";
        _hoverDepth = 0;
        popoutCloseTimer.stop();
    }

    readonly property string popoutCurrent: {
        if (popoutHover) return popoutHover;
        if (popoutForced) return popoutForced;
        if (popped.length > 0) return "notifications";
        return "";
    }
    // Bar reads these for icon highlight when the matching popout is shown.
    readonly property bool notifOpen:    popoutCurrent === "notifications"
    readonly property bool volumeOpen:   popoutCurrent === "volume"
    readonly property bool calendarOpen: popoutCurrent === "calendar"
    readonly property bool powerOpen:    popoutCurrent === "power"

    // -- notification daemon ---------------------------------------------
    // registers as the freedesktop notification server (replaces swaync). new
    // notifications are tracked (so the center can render them) AND pushed to
    // `popped` for ~5s so the panel auto-pops in compact form.
    property var popped: []

    // Per-notification arrival timestamp, keyed by Notification.id (uint32
    // from the D-Bus protocol). Reassigned wholesale on insert/delete so
    // QML re-evaluates bound age labels. _notifNow ticks every 30 s — coarse
    // enough to not redraw constantly, fine enough that "Xm ago" stays right.
    property var notifReceivedAt: ({})
    property real _notifNow: Date.now()
    Timer {
        interval: 30000
        running: true; repeat: true
        onTriggered: shellRoot._notifNow = Date.now()
    }

    function popNotif(n) {
        var copy = Object.assign({}, notifReceivedAt);
        copy[n.id] = Date.now();
        notifReceivedAt = copy;

        popped = [...popped, n];
        // remove from popped the moment the notification closes (e.g. when
        // a default action invocation causes the sender to close it),
        // otherwise popped would hold a dangling pointer until the 5s timer
        // fires — accessing it crashes Quickshell during Repeater regenerate.
        n.closed.connect(() => {
            shellRoot.expirePopped(n);
            var c2 = Object.assign({}, shellRoot.notifReceivedAt);
            delete c2[n.id];
            shellRoot.notifReceivedAt = c2;
        });
        popTimerComp.createObject(shellRoot, { notif: n });
    }
    function expirePopped(n) { popped = popped.filter(x => x !== n); }
    function clearAllNotifs() {
        var all = notifSrv.trackedNotifications.values.slice();
        for (var i = 0; i < all.length; i++) all[i].dismiss();
        popped = [];
    }

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

    // -- app launcher state + IPC ----------------------------------------
    // trigger from hyprland: `qs ipc call launcher toggle`
    property bool launcherOpen: false
    function launcherShow()   { launcherOpen = true;  }
    function launcherHide()   { launcherOpen = false; }
    function launcherToggle() { launcherOpen = !launcherOpen; }

    IpcHandler {
        target: "launcher"
        function show()   { shellRoot.launcherShow();   }
        function hide()   { shellRoot.launcherHide();   }
        function toggle() { shellRoot.launcherToggle(); }
    }

    // PowerMenu is now part of the unified Popouts wrapper. IPC bridges
    // into popoutShow/Hide/Toggle keyed by name = "power".
    IpcHandler {
        target: "power"
        function show()   { shellRoot.popoutShow("power");                              }
        function hide()   { shellRoot.popoutHide();                                     }
        function toggle() {
            if (shellRoot.popoutCurrent === "power") shellRoot.popoutHide();
            else shellRoot.popoutShow("power");
        }
    }

    // -- session lock + IPC ----------------------------------------------
    // trigger: `qs ipc call lock lock` (or PowerMenu's Lock button)
    Lock {
        id: lockObj
        cBg: shellRoot.colors ? shellRoot.colors.ui.bg : "#1e1e2e"  // opaque bg on the lock surface
        cFg: shellRoot.cFg
        cPrimary: shellRoot.cPrimary
        cMuted: shellRoot.cMuted
        cRed: shellRoot.cRed
        fontFamily: shellRoot.fontFamily
    }

    IpcHandler {
        target: "lock"
        function lock() { lockObj.lock(); }
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
    // -- ready gate ------------------------------------------------------
    // Hold off instantiating any per-screen components until colors are
    // loaded. Otherwise QtQuick.Shape paints once with the fallback color
    // and won't repaint on subsequent fillColor binding updates, leaving
    // the bar's inverse corners and theme-switcher peek strip stuck on the
    // launch fallback color.
    readonly property var _screensWhenReady:
        (appliedReady && colors !== null) ? Quickshell.screens : []

    // Per-screen anchor map. Bar updates its X positions on change,
    // Popouts reads by screen name. Reassigning the whole object (vs
    // mutating in place) is what makes QML re-evaluate the bindings.
    property var _barAnchors: ({})
    function _setBarAnchor(name, b) {
        var copy = Object.assign({}, _barAnchors);
        copy[name] = {
            volumeRightX: b.volumeRightX,
            bellRightX:   b.bellRightX,
            clockLeftX:   b.clockLeftX,
            powerLeftX:   b.powerLeftX
        };
        _barAnchors = copy;
    }

    Variants {
        model: _screensWhenReady
        Bar {
            id: bar
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
            notifOpen:    shellRoot.notifOpen
            powerOpen:    shellRoot.powerOpen
            volumeOpen:   shellRoot.volumeOpen
            calendarOpen: shellRoot.calendarOpen
            onPopoutEnter: (name) => shellRoot.popoutEnter(name)
            onPopoutLeave: shellRoot.popoutLeave()
            onVolumeRightXChanged: shellRoot._setBarAnchor(modelData.name, bar)
            onBellRightXChanged:   shellRoot._setBarAnchor(modelData.name, bar)
            onClockLeftXChanged:   shellRoot._setBarAnchor(modelData.name, bar)
            Component.onCompleted: shellRoot._setBarAnchor(modelData.name, bar)
        }
    }

    // Two Popouts wrappers per screen — one for each side of the bar.
    // Cross-side hover (e.g. calendar → volume) is a close-and-open of
    // two independent windows; no panel slides across the screen.
    Variants {
        model: _screensWhenReady
        Popouts {
            modelData: modelData
            side: "right"
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            current: shellRoot.popoutCurrent
            notifServer: notifSrv
            popped: shellRoot.popped
            notifReceivedAt: shellRoot.notifReceivedAt
            now: shellRoot._notifNow
            expireCallback:   (n) => shellRoot.expirePopped(n)
            clearAllCallback: () => shellRoot.clearAllNotifs()
            volumeRightX: {
                var a = shellRoot._barAnchors[modelData.name];
                return a ? a.volumeRightX : 0;
            }
            bellRightX: {
                var a = shellRoot._barAnchors[modelData.name];
                return a ? a.bellRightX : 0;
            }
            onPanelEnter:   shellRoot.popoutEnter(shellRoot.popoutCurrent || "notifications")
            onPanelLeave:   shellRoot.popoutLeave()
            onRequestClose: shellRoot.popoutHide()
        }
    }
    Variants {
        model: _screensWhenReady
        Popouts {
            modelData: modelData
            side: "left"
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            current: shellRoot.popoutCurrent
            notifServer: notifSrv
            popped: shellRoot.popped
            notifReceivedAt: shellRoot.notifReceivedAt
            now: shellRoot._notifNow
            expireCallback:   (n) => shellRoot.expirePopped(n)
            clearAllCallback: () => shellRoot.clearAllNotifs()
            clockLeftX: {
                var a = shellRoot._barAnchors[modelData.name];
                return a ? a.clockLeftX : 0;
            }
            powerLeftX: {
                var a = shellRoot._barAnchors[modelData.name];
                return a ? a.powerLeftX : 0;
            }
            onPanelEnter:   shellRoot.popoutEnter(shellRoot.popoutCurrent || "calendar")
            onPanelLeave:   shellRoot.popoutLeave()
            onRequestClose: shellRoot.popoutHide()
        }
    }

    // -- EdgeBumper hover registry --------------------------------------
    // Generic per-(modal, screen) hover state. Each non-bar modal that uses
    // an EdgeBumper picks a unique name string and reads/writes through
    // these helpers; map reassignment (vs in-place mutation) is what makes
    // QML re-evaluate the bound externalHovered properties.
    property var _bumperHover: ({})
    function _bumperKey(name, screenName) { return name + "::" + screenName; }
    function _setBumperHover(name, screenName, hovered) {
        var copy = Object.assign({}, _bumperHover);
        copy[_bumperKey(name, screenName)] = hovered;
        _bumperHover = copy;
    }
    function _bumperHovered(name, screenName) {
        return _bumperHover[_bumperKey(name, screenName)] === true;
    }

    Variants {
        model: _screensWhenReady
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
            externalHovered: shellRoot._bumperHovered("themeSwitcher", modelData.name)
        }
    }

    Variants {
        model: _screensWhenReady
        EdgeBumper {
            modelData: modelData
            edge: "bottom"
            hitWidth: 596    // matches ThemeSwitcher.panelTotalWidth
            onBumperEnter: shellRoot._setBumperHover("themeSwitcher", modelData.name, true)
            onBumperLeave: shellRoot._setBumperHover("themeSwitcher", modelData.name, false)
        }
    }


    Variants {
        model: _screensWhenReady
        AppLauncher {
            modelData: modelData
            cBg: shellRoot.cBg
            cFg: shellRoot.cFg
            cPrimary: shellRoot.cPrimary
            cMuted: shellRoot.cMuted
            fontFamily: shellRoot.fontFamily
            open: shellRoot.launcherOpen
            onRequestClose: shellRoot.launcherHide()
        }
    }


}
