//@ pragma UseQApplication

// shell.qml — entry point. Holds shared state (colors, theme, system polling)
// and instantiates one Bar + EdgePopouts wrappers per monitor via Variants.
// All visible chrome lives in Bar.qml / EdgePopouts.qml + content files.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    property real   currentOpacity:   0.7

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
        var opacity = over && over.opacity && over.opacity.bg !== undefined
            ? over.opacity.bg
            : currentOpacity;
        currentOpacity = opacity;
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
            currentAccentHex,
            currentOpacity.toString()
        ];
        writeOverride.running = true;
    }
    function setOpacity(val) {
        currentOpacity = val;
        applyPalette();
    }
    function clearOverride() {
        currentFlavor = "mocha";
        currentAccent = "mauve";
        currentAccentHex = "#cba6f7";
        currentOpacity = 0.7;
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

    // -- workspace thumbnails --------------------------------------------
    // Cached PNGs per workspace id, used by the workspaces overview popout.
    // Stored under XDG_RUNTIME_DIR so the cache is wiped on reboot — no
    // stale-screenshot-from-last-session problem. Captured on every focus
    // change (after a 300 ms settle so the switch animation is done) AND
    // every 5 s while idle on a workspace, so the active thumb stays fresh
    // while the overview sits open.
    readonly property string _workspaceThumbDir:
        Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell/workspace-thumbs"
    function workspaceThumbPath(wsId) {
        return _workspaceThumbDir + "/" + wsId + ".png";
    }
    // Bumped after every successful capture so QML Image re-fetches the
    // file even when the path string hasn't changed (Image caches by URL).
    property int _workspaceThumbVersion: 0

    Process {
        id: _workspaceThumbInit
        running: true
        command: ["sh", "-c", "mkdir -p '" + shellRoot._workspaceThumbDir + "'"]
    }
    Process {
        id: _workspaceThumbCapture
        running: false
        onExited: shellRoot._workspaceThumbVersion += 1
    }
    function captureCurrentWorkspace() {
        var ws = Hyprland.focusedWorkspace;
        if (!ws || !ws.monitor || !ws.monitor.name) return;
        if (_workspaceThumbCapture.running) return;
        var path = workspaceThumbPath(ws.id);
        // Write to .tmp then atomically rename so Image readers never see
        // a half-written PNG.
        _workspaceThumbCapture.command = [
            "sh", "-c",
            "grim -s 0.5 -o '" + ws.monitor.name + "' '" + path + ".tmp' "
                + "&& mv '" + path + ".tmp' '" + path + "'"
        ];
        _workspaceThumbCapture.running = true;
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { _workspaceThumbDelay.restart(); }
    }
    Timer {
        id: _workspaceThumbDelay
        interval: 300
        onTriggered: shellRoot.captureCurrentWorkspace()
    }
    Timer {
        interval: 5000
        running: true; repeat: true
        onTriggered: shellRoot.captureCurrentWorkspace()
    }

    // -- OS id (for the launcher button's distro logo) ------------------
    property string osId: ""
    Process {
        running: true
        command: ["sh", "-c", ". /etc/os-release && printf '%s' \"$ID\""]
        stdout: StdioCollector { onStreamFinished: shellRoot.osId = text.trim() }
    }

    // -- focused monitor (Hyprland) --------------------------------------
    // For IPC-driven and notification-driven actions where there's no bar
    // hover to anchor to, we open on the currently-focused monitor only.
    readonly property string focusedScreen:
        Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.monitor
            ? Hyprland.focusedWorkspace.monitor.name
            : ""

    // -- unified bar-popout state ----------------------------------------
    // All top-bar drop-downs (volume, notifications, calendar, power)
    // share one Popouts wrapper per screen. `popoutHover` / `popoutForced`
    // are global; `_popoutOwner` tracks which screen the popout should
    // appear on (avoids opening on every monitor in multi-screen setups).
    // Popouts instances on non-owner screens render `current = ""`.
    property string popoutHover: ""
    property string popoutForced: ""   // set by IPC; cleared on hover
    property string _popoutOwner: ""
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
        onTriggered: {
            shellRoot.popoutHover = "";
            shellRoot.popoutForced = "";
            shellRoot._popoutOwner = "";
        }
    }
    function popoutEnter(name, screen) {
        _hoverDepth += 1;
        popoutCloseTimer.stop();
        popoutHover = name;
        popoutForced = "";   // hover overrides IPC
        _popoutOwner = screen;
    }
    function popoutLeave() {
        _hoverDepth = Math.max(0, _hoverDepth - 1);
        if (_hoverDepth === 0) popoutCloseTimer.restart();
    }
    function popoutShow(name) {
        popoutCloseTimer.stop();
        popoutForced = name;
        popoutHover = "";
        _popoutOwner = focusedScreen;
    }
    function popoutHide() {
        popoutForced = "";
        popoutHover = "";
        _popoutOwner = "";
        _hoverDepth = 0;
        popoutCloseTimer.stop();
    }

    readonly property string popoutCurrent: {
        if (popoutHover) return popoutHover;
        if (popoutForced) return popoutForced;
        if (popped.length > 0) return "notifications";
        return "";
    }
    // Owner of the popout currently showing. For hover/IPC the owner was
    // captured on enter/show; for auto-popped notifications fall back to
    // the focused monitor so only one screen lights up.
    readonly property string popoutOwner: {
        if (popoutHover || popoutForced) return _popoutOwner;
        if (popped.length > 0) return focusedScreen;
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

    // When true, new notifications are still tracked (and visible in the
    // center via hover) but skip the auto-pop strip. Toggled by clicking
    // the bell icon in the bar.
    property bool notifMuted: false
    function toggleNotifMute() { notifMuted = !notifMuted; }

    function popNotif(n) {
        var copy = Object.assign({}, notifReceivedAt);
        copy[n.id] = Date.now();
        notifReceivedAt = copy;

        // cleanup-on-close runs even for muted notifications, so the
        // received-at map doesn't leak entries.
        n.closed.connect(() => {
            shellRoot.expirePopped(n);
            var c2 = Object.assign({}, shellRoot.notifReceivedAt);
            delete c2[n.id];
            shellRoot.notifReceivedAt = c2;
        });

        if (notifMuted) return;   // don't add to popped or start pop timer

        popped = [...popped, n];
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

    // -- center popouts (launcher + workspaces overview) -----------------
    // Both center-anchored popouts share a single Modal wrapper
    // (CenterPopouts) so they morph between each other the same way the
    // left/right Popouts wrapper morphs volume → notifications. Single
    // hover-depth counter, single close timer, single owner — switching
    // between launcher and workspaces mid-hover is just a `centerCurrent`
    // change, not a separate close-then-open.
    //
    // Dual-mode: when opened by hover (centerEnter), the launcher closes
    // on hover-leave like every other popout. When opened by IPC
    // (centerShow → e.g. launcher keybind), `_centerHoverManaged` is
    // false and hover events are ignored — stays open until centerHide.
    property string centerCurrent: ""
    property string centerOwner: ""
    property int _centerHoverDepth: 0
    property bool _centerHoverManaged: false
    Timer {
        id: centerCloseTimer
        interval: 250
        onTriggered: shellRoot.centerHide()
    }
    function centerEnter(name, screen) {
        if (centerCurrent === "") {
            // Opening from closed — hover is in charge of the lifecycle.
            _centerHoverManaged = true;
        }
        if (!_centerHoverManaged) {
            // IPC-managed launcher: keep open, but allow morphing into
            // workspaces if the user actively hovers it.
            if (name !== centerCurrent) {
                centerCurrent = name;
                centerOwner = screen;
            }
            return;
        }
        _centerHoverDepth += 1;
        centerCloseTimer.stop();
        centerCurrent = name;
        centerOwner = screen;
    }
    function centerLeave() {
        if (!_centerHoverManaged) return;
        _centerHoverDepth = Math.max(0, _centerHoverDepth - 1);
        if (_centerHoverDepth === 0) centerCloseTimer.restart();
    }
    function centerShow(name) {
        _centerHoverManaged = false;
        _centerHoverDepth = 0;
        centerCloseTimer.stop();
        centerOwner = focusedScreen;
        centerCurrent = name;
    }
    function centerHide() {
        centerCurrent = "";
        centerOwner = "";
        _centerHoverDepth = 0;
        _centerHoverManaged = false;
        centerCloseTimer.stop();
    }
    // -- bottom edge popouts (themes; future bottom siblings) -----------
    // Mirrors centerEnter/centerLeave above: a depth counter aggregates
    // hover from the bottom EdgeBumper AND from the cursor crossing onto
    // the panel itself, so the 250 ms grace timer absorbs the brief gap
    // when the cursor moves between the two surfaces. Without this, the
    // panel collapses the moment the cursor leaves the 8 px bumper hit
    // zone, even if it's now on the expanding panel.
    property string bottomCurrent: ""
    property string bottomOwner: ""
    property int _bottomHoverDepth: 0
    Timer {
        id: bottomCloseTimer
        interval: 250
        onTriggered: shellRoot.bottomHide()
    }
    function bottomEnter(name, screen) {
        _bottomHoverDepth += 1;
        bottomCloseTimer.stop();
        bottomCurrent = name;
        bottomOwner = screen;
    }
    function bottomLeave() {
        _bottomHoverDepth = Math.max(0, _bottomHoverDepth - 1);
        if (_bottomHoverDepth === 0) bottomCloseTimer.restart();
    }
    function bottomHide() {
        bottomCurrent = "";
        bottomOwner = "";
        _bottomHoverDepth = 0;
        bottomCloseTimer.stop();
    }

    // Shorthands for the launcher IPC handler — preserves the existing
    // qs ipc surface (`launcher show|hide|toggle`).
    function launcherShow()   { centerShow("launcher"); }
    function launcherHide()   { centerHide(); }
    function launcherToggle() {
        if (centerCurrent === "launcher") centerHide();
        else centerShow("launcher");
    }

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
            volumeRightX:    b.volumeRightX,
            bellRightX:      b.bellRightX,
            clockLeftX:      b.clockLeftX,
            powerLeftX:      b.powerLeftX,
            trayItemRightX:  b.trayItemRightX
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
            notifMuted: shellRoot.notifMuted
            notifOpen:    shellRoot.notifOpen
            powerOpen:    shellRoot.powerOpen
            volumeOpen:   shellRoot.volumeOpen
            calendarOpen: shellRoot.calendarOpen
            osId:         shellRoot.osId
            launcherOpen: (shellRoot.centerCurrent === "launcher" && shellRoot.centerOwner === modelData.name)
            workspacesOpen: (shellRoot.centerCurrent === "workspaces" && shellRoot.centerOwner === modelData.name)
            onPopoutEnter: (name) => {
                if (name === "launcher" || name === "workspaces") {
                    shellRoot.centerEnter(name, modelData.name);
                } else {
                    shellRoot.popoutEnter(name, modelData.name);
                }
            }
            onPopoutLeave: (name) => {
                if (name === "launcher" || name === "workspaces") {
                    shellRoot.centerLeave();
                } else {
                    shellRoot.popoutLeave();
                }
            }
            onNotifMuteToggle: shellRoot.toggleNotifMute()
            onVolumeRightXChanged:   shellRoot._setBarAnchor(modelData.name, bar)
            onBellRightXChanged:     shellRoot._setBarAnchor(modelData.name, bar)
            onClockLeftXChanged:     shellRoot._setBarAnchor(modelData.name, bar)
            onTrayItemRightXChanged: shellRoot._setBarAnchor(modelData.name, bar)
            Component.onCompleted:   shellRoot._setBarAnchor(modelData.name, bar)
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
            // Show only if this screen owns the popout. Other screens
            // get current="" so their wrapper stays closed.
            current: shellRoot.popoutOwner === modelData.name ? shellRoot.popoutCurrent : ""
            interactive: shellRoot.popoutHover !== "" || shellRoot.popoutForced !== ""
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
            trayItemRightX: {
                var a = shellRoot._barAnchors[modelData.name];
                return a ? a.trayItemRightX : 0;
            }
            onPanelEnter:   shellRoot.popoutEnter(shellRoot.popoutCurrent || "notifications", modelData.name)
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
            current: shellRoot.popoutOwner === modelData.name ? shellRoot.popoutCurrent : ""
            interactive: shellRoot.popoutHover !== "" || shellRoot.popoutForced !== ""
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
            onPanelEnter:   shellRoot.popoutEnter(shellRoot.popoutCurrent || "calendar", modelData.name)
            onPanelLeave:   shellRoot.popoutLeave()
            onRequestClose: shellRoot.popoutHide()
        }
    }

    // Bottom EdgePopouts wrappers. Two panels — themes (centered) and
    // minigame (bottom-left) — each with its own permanent 8 px peek
    // strip. They share `bottomCurrent` + `bottomEnter`/`bottomLeave`,
    // so sliding between bumpers updates the shared name, both wrappers
    // re-evaluate `current`, and one panel collapses while the other
    // expands in the same animation frame (simultaneous morph rather
    // than close-then-open).
    //
    // Bottom EdgePopouts — hosts the ThemeSwitcher (and any future
    // bottom-edge siblings) with peekHeight: 8 so the panel stays mounted
    // as a thin sliver until the bottom edge bumper triggers it open.
    Variants {
        model: _screensWhenReady
        EdgePopouts {
            id: themesEdge
            modelData: modelData
            edge: "bottom"
            cBg: shellRoot.cBg
            peekHeight: 8
            peekDefault: "themes"
            current: (shellRoot.bottomOwner === modelData.name && shellRoot.bottomCurrent === "themes")
                ? "themes" : ""
            // Cursor on this panel keeps the same depth counter the bumpers
            // increment, so crossing bumper → panel doesn't drop hover.
            onPanelEnter: shellRoot.bottomEnter("themes", modelData.name)
            onPanelLeave: shellRoot.bottomLeave()
            contents: [
                { name: "themes", source: themesContentComp },
            ]

            Component {
                id: themesContentComp
                ThemeSwitcherContent {
                    cFg:                shellRoot.cFg
                    cPrimary:           shellRoot.cPrimary
                    cMuted:             shellRoot.cMuted
                    fontFamily:         shellRoot.fontFamily
                    mochaAccents:       shellRoot.mochaAccents
                    currentFlavor:      shellRoot.currentFlavor
                    currentOpacity:     shellRoot.currentOpacity
                    setAccent:          (name, hex) => shellRoot.setAccent(name, hex)
                    toggleFlavor:       () => shellRoot.toggleFlavor()
                    clearOverride:      () => shellRoot.clearOverride()
                    setOpacity:         (val) => shellRoot.setOpacity(val)
                    panelVisibleHeight: themesEdge.visibleHeight
                    peekHeight:         themesEdge.peekHeight
                }
            }
        }
    }

    Variants {
        model: _screensWhenReady
        EdgePopouts {
            id: minigameEdge
            modelData: modelData
            edge: "bottom"
            cBg: shellRoot.cBg
            peekHeight: 8
            peekDefault: "minigame"
            // Center the panel in the available space between screen-left
            // and the themes panel's left edge. Themes is screen-centered
            // with total width 596, so its left edge is at (W - 596)/2.
            // Minigame panel is also 596 wide; we want its center at the
            // midpoint of [0, (W - 596)/2], i.e. (W - 596)/4. Offset from
            // screen center (W/2) is therefore -(W + 596)/4.
            panelXOffset: -(width + 596) / 4
            current: (shellRoot.bottomOwner === modelData.name && shellRoot.bottomCurrent === "minigame")
                ? "minigame" : ""
            onPanelEnter: shellRoot.bottomEnter("minigame", modelData.name)
            onPanelLeave: shellRoot.bottomLeave()
            contents: [
                { name: "minigame", source: minigameContentComp },
            ]

            Component {
                id: minigameContentComp
                MinigameContent {
                    cFg:                shellRoot.cFg
                    cPrimary:           shellRoot.cPrimary
                    cMuted:             shellRoot.cMuted
                    fontFamily:         shellRoot.fontFamily
                    panelVisibleHeight: minigameEdge.visibleHeight
                    peekHeight:         minigameEdge.peekHeight
                    // Run the game only while the window is fully open;
                    // peek collapses unload the gameplay Loader entirely
                    // (timers + animations destroyed). Score persists
                    // across reopen on MinigameContent itself.
                    // Use minigameEdge.current rather than shellRoot
                    // bottomCurrent + bottomOwner so we don't have to
                    // resolve modelData across Component boundaries.
                    active: minigameEdge.current === "minigame"
                }
            }
        }
    }

    // Mania (osu!mania) — third bottom panel, mirror of minigame on the
    // RIGHT of themes. Same gap math as minigame but reflected: panel
    // center at (3W + 596) / 4, so panelXOffset = +(W + 596) / 4.
    Variants {
        model: _screensWhenReady
        EdgePopouts {
            id: maniaEdge
            modelData: modelData
            edge: "bottom"
            cBg: shellRoot.cBg
            peekHeight: 8
            peekDefault: "mania"
            // Grab kbd focus while playing so D/F/J/K hit the gameplay
            // Item's Keys.onPressed instead of the focused app.
            kbdFocusName: "mania"
            kbdExclusive: true
            panelXOffset: (width + 596) / 4
            current: (shellRoot.bottomOwner === modelData.name && shellRoot.bottomCurrent === "mania")
                ? "mania" : ""
            onPanelEnter: shellRoot.bottomEnter("mania", modelData.name)
            onPanelLeave: shellRoot.bottomLeave()
            contents: [
                { name: "mania", source: maniaContentComp },
            ]

            Component {
                id: maniaContentComp
                ManiaContent {
                    cFg:                shellRoot.cFg
                    cPrimary:           shellRoot.cPrimary
                    cMuted:             shellRoot.cMuted
                    fontFamily:         shellRoot.fontFamily
                    panelVisibleHeight: maniaEdge.visibleHeight
                    peekHeight:         maniaEdge.peekHeight
                    active:             maniaEdge.current === "mania"
                }
            }
        }
    }

    // Themes bumper — centered hit zone matching ThemeSwitcher's panel width.
    Variants {
        model: _screensWhenReady
        EdgeBumper {
            modelData: modelData
            edge: "bottom"
            hitWidth: 596    // matches ThemeSwitcherContent panel total width
            onBumperEnter: shellRoot.bottomEnter("themes", modelData.name)
            onBumperLeave: shellRoot.bottomLeave()
        }
    }
    // Mania bumper — centered in the gap right of themes. Mirror of the
    // minigame bumper formula: hitX = themes-right-edge + (gap - hitWidth)/2.
    Variants {
        model: _screensWhenReady
        EdgeBumper {
            modelData: modelData
            edge: "bottom"
            hitWidth: 596
            // Themes right edge = (W + 596)/2; available right gap width =
            // (W - 596)/2; want hit zone centered in [themes-right, W].
            // hitX = (W + 596)/2 + ((W - 596)/2 - 596)/2 = (3W - 596)/4.
            hitX: (3 * width - 596) / 4
            onBumperEnter: shellRoot.bottomEnter("mania", modelData.name)
            onBumperLeave: shellRoot.bottomLeave()
        }
    }
    // Minigame bumper — centered in the gap between screen-left and the
    // themes bumper. Same hit zone width as the panel (596), positioned
    // at (gap_width - hitWidth) / 2 = (W - 1788) / 4.
    Variants {
        model: _screensWhenReady
        EdgeBumper {
            modelData: modelData
            edge: "bottom"
            hitWidth: 596    // = MinigameContent panel total width
            hitX: (width - 1788) / 4
            onBumperEnter: shellRoot.bottomEnter("minigame", modelData.name)
            onBumperLeave: shellRoot.bottomLeave()
        }
    }


    // Top EdgePopouts wrapper — hosts the AppLauncher and workspaces
    // overview as crossfading Loaders so they morph between each other
    // (same pattern as Popouts.qml does for left/right side popouts).
    Variants {
        model: _screensWhenReady
        EdgePopouts {
            id: topEdge
            modelData: modelData
            edge: "top"
            cBg: shellRoot.cBg
            current: shellRoot.centerOwner === modelData.name
                ? shellRoot.centerCurrent
                : ""
            ipcContentName: "launcher"
            ipcManaged: !shellRoot._centerHoverManaged
            contents: [
                { name: "launcher",   source: launcherContentComp },
                { name: "workspaces", source: workspacesContentComp },
            ]
            // Hover handoff: cursor on the panel keeps the same depth
            // counter the bar icons increment, so crossing icon → panel
            // never drops to zero.
            onPanelEnter: shellRoot.centerEnter(shellRoot.centerCurrent || "launcher", modelData.name)
            onPanelLeave: shellRoot.centerLeave()
            onRequestClose: shellRoot.centerHide()
            // Launcher needs keyboard focus on its search input when it
            // becomes the active content (IPC summon, hover summon, or
            // morph from workspaces).
            onContentActivated: name => {
                if (name === "launcher") {
                    var l = topEdge._loaderByName["launcher"];
                    if (l && l.item) l.item.focusSearch();
                }
            }

            Component {
                id: launcherContentComp
                AppLauncherContent {
                    cFg:        shellRoot.cFg
                    cPrimary:   shellRoot.cPrimary
                    cMuted:     shellRoot.cMuted
                    fontFamily: shellRoot.fontFamily
                    onRequestClose: shellRoot.centerHide()
                }
            }
            Component {
                id: workspacesContentComp
                WorkspacesContent {
                    cBg:          shellRoot.cBg
                    cFg:          shellRoot.cFg
                    cPrimary:     shellRoot.cPrimary
                    cMuted:       shellRoot.cMuted
                    fontFamily:   shellRoot.fontFamily
                    thumbDir:     shellRoot._workspaceThumbDir
                    thumbVersion: shellRoot._workspaceThumbVersion
                    onRequestClose: shellRoot.centerHide()
                }
            }
        }
    }

}
