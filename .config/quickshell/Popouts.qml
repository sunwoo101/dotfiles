// Popouts — single PanelWindow that hosts every top-bar drop-down popout
// (volume, notifications, calendar, power). The wrapper window stays
// mounted; switching is a morph: animate panel.x, .width, .height in
// lockstep while content fades. Same window — no parallel-window jitter,
// no inverse-corner separation.
//
// Each popout has an anchor — where its panel aligns along the bar:
//   • side "right": panel right edge at anchor X (volume, notifications)
//   • side "left":  panel left  edge at anchor X (calendar, power)
//
// Corners adapt:
//   • Outer (top) corners: inverse (carve into bar) when not at a screen
//     edge; flush at the screen edge.
//   • Bottom corners: rounded when not at a screen edge; flush otherwise.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: root

    required property var modelData
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    // Which side of the bar this wrapper handles. "right" hosts volume +
    // notifications; "left" hosts calendar + power. Two separate wrappers
    // are instantiated so cross-side hover (e.g. calendar → volume) is a
    // close-and-open of two independent windows, not a slide across the
    // screen with one wrapper.
    required property string side          // "left" | "right"

    required property string current       // global popout name (or "")
    // True when the popout is open due to user hover/click, false when it's
    // an auto-popped notification toast. Drives toast-vs-full UI in
    // NotificationsContent (clear-all button, full list).
    required property bool interactive
    required property var notifServer
    required property var popped
    required property var notifReceivedAt
    required property real now
    required property var expireCallback
    required property var clearAllCallback

    // anchor X positions (screen coords) supplied by Bar
    property real volumeRightX: 0
    property real bellRightX:   0
    property real clockLeftX:   0
    property real powerLeftX:   0
    // single live tray anchor — Bar updates it on each tray-icon onEntered.
    // Per-icon morph happens because the popout NAME ("tray:N") changes,
    // which retriggers curConfig + the imperative anchor animation.
    property real trayItemRightX: 0

    signal panelEnter()
    signal panelLeave()
    signal requestClose()

    screen: modelData
    color: "transparent"
    // 0 makes the popout respect the bar's reserved exclusive zone, so
    // the popout's surface starts at screen y = barHeight (no overlap).
    // The mask below covers the full panel area in root coords (which
    // already starts below the bar — no offset needed).
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayershell.Overlay

    readonly property int barHeight:    48
    readonly property int invRadius:    18
    readonly property int cornerRadius: 14
    readonly property int animDuration: Anims.panel

    // Only handle popouts that belong to OUR side.
    function _config(name) {
        if (name === "volume" && side === "right")
            return { side: "right", anchor: volumeRightX, item: volumeLoader.item };
        if (name === "notifications" && side === "right")
            return { side: "right", anchor: root.width,   item: notifLoader.item };
        if (name === "calendar" && side === "left")
            return { side: "left",  anchor: clockLeftX,   item: calLoader.item };
        if (name === "power" && side === "left")
            return { side: "left",  anchor: powerLeftX,   item: powerLoader.item };
        if (name && name.indexOf("tray:") === 0 && side === "right")
            return { side: "right", anchor: trayItemRightX,
                     item: root._traySlot === 0 ? trayLoaderA.item : trayLoaderB.item };
        return null;
    }
    // Index into SystemTray.items.values for the currently-hovered tray
    // icon, derived from popout name "tray:N".
    readonly property int _trayIndex: {
        if (!current || current.indexOf("tray:") !== 0) return -1;
        var n = parseInt(current.substring(5));
        return isNaN(n) ? -1 : n;
    }
    readonly property var _trayItem: {
        if (_trayIndex < 0) return null;
        var items = SystemTray.items.values;
        return _trayIndex < items.length ? items[_trayIndex] : null;
    }

    // Ping-pong tray slots — two loaders that cross-fade like every other
    // content pair. _traySlot (0 or 1) tracks which is foreground; on each
    // _trayIndex change we write the new item into the background slot then
    // flip _traySlot so the Behavior on opacity handles the simultaneous
    // fade-out / fade-in automatically.
    property int _traySlot:  0
    property var _trayItemA: null   // item shown by trayLoaderA
    property var _trayItemB: null   // item shown by trayLoaderB

    Connections {
        target: root
        function on_TrayIndexChanged() {
            if (root._trayIndex >= 0) {
                var other = 1 - root._traySlot;
                if (other === 0) root._trayItemA = root._trayItem;
                else             root._trayItemB = root._trayItem;
                root._traySlot = other;
            }
            // leaving tray: opacity bindings drop both loaders to 0
        }
    }

    readonly property var curConfig: _config(current)
    readonly property bool _isOpen: curConfig !== null
    readonly property real _targetW: curConfig && curConfig.item ? curConfig.item.implicitWidth  : 0
    readonly property real _targetH: curConfig && curConfig.item ? curConfig.item.implicitHeight : 0
    readonly property int  _panelWidth: _isOpen ? _targetW + 2 * invRadius : 0

    // _activeAnchor is the panel EDGE X (right edge for right-side panels,
    // left edge for left-side). Always offset by invRadius from the content
    // anchor so the corner overhang is consistent on both sides.
    property real _activeAnchor: 0
    property var _prevCur: null
    Behavior on _activeAnchor {
        id: _anchorBehavior
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
    }
    // _targetH can change AFTER curConfig has stabilized — async content
    // load (tray menu items arriving via SNI, notifications list growing).
    // Without this, _surfaceH stays at whatever value it had when the
    // popout first opened (often 0, when the inner item.implicitHeight
    // hadn't resolved yet), and the panel renders into a 0-height surface
    // (i.e. nothing visible). Subsequent popout switches recover because
    // onCurConfigChanged re-runs the grow check.
    Connections {
        target: root
        function on_TargetHChanged() {
            if (root._isOpen && root._targetH > root._surfaceH) {
                root._surfaceH = root._targetH;
            }
        }
    }

    Connections {
        target: root
        function onCurConfigChanged() {
            var prev = root._prevCur;
            var cur = root.curConfig;
            root._prevCur = cur;
            var screenEdge = root.side === "right" ? root.width : 0;
            if (!cur) {
                // closing — slide the anchor edge out toward the screen edge
                root._activeAnchor = screenEdge;
                // Hold the surface height; collapse only after the inner
                // panel finishes animating. Prevents the ghost-buffer halo.
                _surfaceCollapseTimer.restart();
                return;
            }
            // opening or switching: surface only GROWS (never shrinks
            // mid-session). Shrinking surface mid-morph would cut off the
            // outgoing panel and re-trigger the ghost-buffer halo. The
            // surface only collapses to 0 after a full close (timer below).
            _surfaceCollapseTimer.stop();
            if (root._targetH > root._surfaceH) root._surfaceH = root._targetH;
            var panelAnchor = (cur.side === "right")
                ? cur.anchor + root.invRadius
                : cur.anchor - root.invRadius;
            if (!prev) {
                // opening from closed — snap to screen edge, then animate to target
                _anchorBehavior.enabled = false;
                root._activeAnchor = screenEdge;
                _anchorBehavior.enabled = true;
                root._activeAnchor = panelAnchor;
                return;
            }
            root._activeAnchor = panelAnchor;
        }
    }

    // -- root window ---------------------------------------------------
    anchors { top: true; left: true; right: true }
    margins.top: 0

    // Inner panel height — animates smoothly. The Wayland surface height
    // (implicitHeight) is decoupled and held during the close animation:
    // shrinking the surface mid-anim causes the compositor to keep the
    // previous-frame buffer onscreen for a frame, manifesting as an
    // unrounded window halo around the collapsing Shape (same ghost-buffer
    // class as ThemeSwitcher's surface resize). Holding the surface at the
    // open size and only animating the inner panel keeps the SVG and the
    // surface visually in lockstep.
    property real _innerH: _isOpen ? _targetH : 0
    Behavior on _innerH {
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
    }
    // Surface height — no Behavior. Snaps up on open/switch; only drops to
    // 0 once the inner panel has fully collapsed (timer below).
    property real _surfaceH: 0
    implicitHeight: _surfaceH
    Timer {
        id: _surfaceCollapseTimer
        interval: root.animDuration + 20
        onTriggered: if (!root._isOpen) root._surfaceH = 0
    }

    // input mask: panel area only — passes input on regions outside the
    // panel through to whatever's below. The popout doesn't overlap the
    // bar (exclusiveZone: 0 keeps it below), so we don't need to cut a
    // bar strip; the mask covers the full panel rect.
    mask: Region {
        x: panel.x
        y: 0
        width: panel.width
        height: panel.height
    }

    // root-level HoverHandler — tracks hover across the entire input mask
    // region. Previously this was on `panel`, which has clip:true and may
    // interfere with hover tracking near the edges; root window doesn't.
    HoverHandler {
        onHoveredChanged: hovered ? root.panelEnter() : root.panelLeave()
    }

    // -- panel ---------------------------------------------------------
    Item {
        id: panel

        // x derived from _activeAnchor (panel edge) and animated width.
        // No Behavior on x — it tracks panel.width which has the Behavior,
        // so as width grows 0 → target, x follows and the panel edge stays
        // pinned. _activeAnchor is the panel right edge (right side) or left
        // edge (left side), so no offset term is needed here.
        x: root.side === "right"
            ? root._activeAnchor - panel.width
            : root._activeAnchor
        width:  root._panelWidth
        height: root._innerH
        anchors.top: parent.top

        Behavior on width {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }

        clip: true   // hide content overflow during morph
        // HoverHandler is at root level (above) — keeps it independent of
        // this Item's clip and explicit width/x animations.

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: 0
                fillColor: root.cBg
                PathSvg { path: root._svgPath }
            }
        }

        Item {
            id: contentArea
            anchors.fill: parent
            anchors.leftMargin:  root.invRadius
            anchors.rightMargin: root.invRadius
            // Clip to the Shape's body region (panel rect minus inverse-corner
            // insets). Loaders inside are anchored to one edge with a fixed
            // implicitWidth — when the panel morphs to a narrower target,
            // the outgoing content's far edge would otherwise slide into the
            // inverse-corner area (transparent, outside the Shape fill) and
            // be visible during the cross-fade. Panel-level clip:true uses
            // the rectangular bounding box, not the Shape path, so it can't
            // catch this on its own.
            clip: true

            // Right-pinned content (right-side popouts).
            Loader {
                id: volumeLoader
                anchors.right: parent.right
                anchors.top:   parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "right"
                opacity: root.current === "volume" ? 1 : 0
                // Disable input when not the active popout — otherwise
                // clicks pass through the visible content to whichever
                // Loader is behind. ESPECIALLY important for Power, which
                // has shutdown/reboot/logout under invisible CardButtons.
                enabled: root.current === "volume"
                // Bump active Loader z above sibling Loaders so hover
                // events reach its descendants. On Qt6/Wayland, click
                // events propagate through disabled siblings but hover
                // events do NOT — without this z bump, an overlapping
                // disabled Loader (e.g. Power's 520×160 footprint) blocks
                // hover for the active popout's small buttons.
                z: root.current === "volume" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: VolumeContent {
                    cFg: root.cFg
                    cPrimary: root.cPrimary
                    cMuted: root.cMuted
                    fontFamily: root.fontFamily
                }
            }
            Loader {
                id: notifLoader
                anchors.right: parent.right
                anchors.top:   parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "right"
                opacity: root.current === "notifications" ? 1 : 0
                enabled: root.current === "notifications"
                z: root.current === "notifications" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: NotificationsContent {
                    notifServer:      root.notifServer
                    popped:           root.popped
                    notifReceivedAt:  root.notifReceivedAt
                    now:              root.now
                    expireCallback:   root.expireCallback
                    clearAllCallback: root.clearAllCallback
                    hovered:          root.current === "notifications" ? root.interactive : notifLoader.opacity > 0
                    cFg:              root.cFg
                    cPrimary:         root.cPrimary
                    cMuted:           root.cMuted
                    fontFamily:       root.fontFamily
                }
            }
            // Tray menu — two loaders that cross-fade like every other content
            // pair. _traySlot picks which is foreground; opacity Behaviors
            // handle the simultaneous fade-in / fade-out.
            Loader {
                id: trayLoaderA
                anchors.right: parent.right
                anchors.top:   parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "right"
                opacity: root._traySlot === 0 && root._trayIndex >= 0 ? 1 : 0
                enabled: root._traySlot === 0 && root._trayIndex >= 0
                z: root._traySlot === 0 && root._trayIndex >= 0 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: TrayMenuContent {
                    trayItem:   root._trayItemA
                    cBg:        root.cBg
                    cFg:        root.cFg
                    cPrimary:   root.cPrimary
                    cMuted:     root.cMuted
                    fontFamily: root.fontFamily
                    onRequestClose: root.requestClose()
                }
            }
            Loader {
                id: trayLoaderB
                anchors.right: parent.right
                anchors.top:   parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "right"
                opacity: root._traySlot === 1 && root._trayIndex >= 0 ? 1 : 0
                enabled: root._traySlot === 1 && root._trayIndex >= 0
                z: root._traySlot === 1 && root._trayIndex >= 0 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: TrayMenuContent {
                    trayItem:   root._trayItemB
                    cBg:        root.cBg
                    cFg:        root.cFg
                    cPrimary:   root.cPrimary
                    cMuted:     root.cMuted
                    fontFamily: root.fontFamily
                    onRequestClose: root.requestClose()
                }
            }
            // Left-pinned content (left-side popouts).
            Loader {
                id: calLoader
                anchors.left: parent.left
                anchors.top:  parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "left"
                opacity: root.current === "calendar" ? 1 : 0
                enabled: root.current === "calendar"
                z: root.current === "calendar" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: CalendarContent {
                    cBg: root.cBg
                    cFg: root.cFg
                    cPrimary: root.cPrimary
                    cMuted: root.cMuted
                    fontFamily: root.fontFamily
                }
            }
            Loader {
                id: powerLoader
                anchors.left: parent.left
                anchors.top:  parent.top
                width:  item ? item.implicitWidth  : 0
                height: item ? item.implicitHeight : 0
                active: root.side === "left"
                opacity: root.current === "power" ? 1 : 0
                enabled: root.current === "power"
                z: root.current === "power" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
                }
                sourceComponent: PowerMenuContent {
                    cFg: root.cFg
                    cPrimary: root.cPrimary
                    cMuted: root.cMuted
                    fontFamily: root.fontFamily
                    onRequestClose: root.requestClose()
                }
            }
        }
    }

    // -- SVG path: TL + TR inverse cusps, BL + BR rounded corners, no edge cases.
    readonly property string _svgPath: {
        var W  = panel.width;
        var H  = panel.height;
        var R  = Math.min(invRadius,    H / 2);
        var bR = Math.min(cornerRadius, H / 2);
        return "M 0 0 L " + W + " 0 "
            + "A " + R  + " " + R  + " 0 0 0 " + (W-R)     + " " + R      + " "
            + "L " + (W-R)     + " " + (H-bR)  + " "
            + "A " + bR + " " + bR + " 0 0 1 " + (W-R-bR)  + " " + H      + " "
            + "L " + (R+bR)    + " " + H        + " "
            + "A " + bR + " " + bR + " 0 0 1 " + R          + " " + (H-bR) + " "
            + "L " + R         + " " + R         + " "
            + "A " + R  + " " + R  + " 0 0 0 0 0 Z";
    }
}
