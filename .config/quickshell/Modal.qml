// Modal — base for hover/IPC-driven panels that hang from the bar (top edge)
// or the screen bottom. Renders a unified Shape outline with edge-aware
// corner curves: inverse curves on the side that "merges" with the bar/edge
// (carved-in look), rounded curves on the opposite side, and flush corners
// where the panel meets a screen edge.
//
// Children declared inside Modal land inside `contentArea`, which is already
// inset to avoid the inverse-corner regions.
//
// Configuration:
//   edge:  "top" | "bottom"        — which screen edge it hangs from
//   align: "left" | "right" | "center" — position along that edge
// Corner types are derived: corners on the merge edge become inverse (or
// flush if also on a screen edge), corners on the opposite edge become
// rounded.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    required property color cBg

    property string edge:  "top"      // "top" | "bottom"
    property string align: "left"     // "left" | "right" | "center"

    property int contentWidth:  480
    property int contentHeight: 200
    property int invRadius:     18
    property int cornerRadius:  16
    property int animDuration:  280

    // Toggle for the Behavior on `panel.width`. Subclasses that want to
    // snap width without animating (e.g. EdgePopouts on open-from-closed
    // transitions, where the diagonal grow looks wrong and only height
    // should animate) set this to false around the assignment that should
    // snap, then back to true. Mirrors the _anchorBehavior trick in
    // Popouts.qml.
    property bool animatePanelWidth: true

    // Horizontal offset from the centered position (only meaningful when
    // align === "center"). EdgePopouts uses this to morph the panel
    // between named anchor positions while keeping a single PanelWindow
    // surface (mirrors Popouts.qml's `_activeAnchor` pattern). Animated
    // 280 ms OutCubic, gated by `animatePanelXOffset`.
    property real panelXOffset: 0
    property bool animatePanelXOffset: true

    // PanelWindow surface size — drives the Wayland layer-shell surface.
    // Defaults to tracking contentHeight, so most modals (AppLauncher) animate
    // their surface together with the inner panel. Override (e.g.
    // ThemeSwitcher) to a constant value to keep the surface from resizing
    // during inner-panel animation — avoids compositor ghost artifacts when
    // the layer surface shrinks repeatedly under hover toggling.
    property int surfaceHeight: contentHeight

    property bool open: false
    // When true, the PanelWindow spans the full screen while open and a
    // transparent MouseArea behind the visible panel closes the modal on
    // outside click. Used by IPC-driven modals like AppLauncher.
    property bool closeOnOutsideClick: false

    signal panelEnter()
    signal panelLeave()
    signal requestClose()

    default property alias contentChildren: contentArea.data
    // Animated inner-panel height — for subclasses that fade content with
    // the panel collapse (separate from implicitHeight, which may be a
    // constant surface size when surfaceHeight is overridden).
    readonly property alias visibleHeight: panel.height

    screen: modelData
    color: "transparent"
    exclusiveZone: 0

    // Overlay (above the bar's Top) so the cursor at the modal's top edge
    // — where the inverse corner overlaps the bar — stays on the modal
    // surface. Otherwise the bar steals focus there and HoverHandler closes.
    WlrLayershell.layer: WlrLayershell.Overlay

    // -- corner type derivation ------------------------------------------
    // Outer edge merges with bar/screen via inverse corners; opposite edge
    // is rounded; corners that meet a screen edge are flush.
    readonly property bool isCenter: align === "center"
    readonly property bool touchesLeftScreenEdge:  align === "left"
    readonly property bool touchesRightScreenEdge: align === "right"

    function _cornerType(corner) {
        var onTop    = corner === "TL" || corner === "TR";
        var onLeft   = corner === "TL" || corner === "BL";
        var onOuter  = (edge === "top") ? onTop : !onTop;
        var onScreenEdge = (onLeft && touchesLeftScreenEdge)
                        || (!onLeft && touchesRightScreenEdge);
        if (onScreenEdge) return "flush";
        return onOuter ? "inverse" : "rounded";
    }

    readonly property string cornerTL: _cornerType("TL")
    readonly property string cornerTR: _cornerType("TR")
    readonly property string cornerBR: _cornerType("BR")
    readonly property string cornerBL: _cornerType("BL")

    // -- panel total width (visible content + inverse corner regions) ----
    readonly property int leftInverseWidth:
        (cornerTL === "inverse" || cornerBL === "inverse") ? invRadius : 0
    readonly property int rightInverseWidth:
        (cornerTR === "inverse" || cornerBR === "inverse") ? invRadius : 0
    readonly property int panelTotalWidth:
        contentWidth + leftInverseWidth + rightInverseWidth

    // -- root anchoring + sizing -----------------------------------------
    // When closeOnOutsideClick, expand the PanelWindow to fill the screen so
    // the outside-click catcher has somewhere to live. Otherwise anchor only
    // to the configured edges and let implicitHeight drive the size.
    //
    // _fullscreen lingers for the close animation duration so panel.height
    // can animate 520→0 before the layer reverts to non-fullscreen anchors.
    property bool _animatingClose: false
    readonly property bool _fullscreen: closeOnOutsideClick && (open || _animatingClose)
    onOpenChanged: {
        if (open) {
            _animatingClose = false;
            _closeAnimTimer.stop();
            _surfaceCollapseTimer.stop();
            if (surfaceHeight > _surfaceH) _surfaceH = surfaceHeight;
        } else {
            if (closeOnOutsideClick) {
                _animatingClose = true;
                _closeAnimTimer.restart();
            }
            _surfaceCollapseTimer.restart();
        }
    }
    Timer {
        id: _closeAnimTimer
        interval: root.animDuration
        onTriggered: root._animatingClose = false
    }
    anchors {
        top:    _fullscreen || edge === "top"
        bottom: _fullscreen || edge === "bottom"
        left:   _fullscreen || isCenter || align === "left"
        right:  _fullscreen || isCenter || align === "right"
    }
    margins.top:    0
    margins.bottom: 0

    // Animate both width and height (when not centered/fullscreen) so the
    // panel grows diagonally from its anchor corner — matches the Popouts
    // wrapper's sliding-drawer feel for visual consistency.
    implicitWidth:  isCenter
        ? -1
        : (open ? panelTotalWidth : 0)
    Behavior on implicitWidth {
        enabled: !isCenter && !_fullscreen
        NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
    }

    // Wayland surface height — decoupled from the inner-panel animation.
    // Snaps up when opening (or when surfaceHeight grows mid-session, e.g.
    // CenterPopouts switching launcher↔workspaces with different content
    // heights), and only drops to 0 after the inner panel has fully
    // collapsed (timer below). Animating the surface in lockstep with the
    // inner panel makes the compositor hold the previous-frame buffer for
    // a frame on close, which renders as an unrounded rectangular halo
    // around the shrinking Shape. Surface NEVER shrinks while mounted —
    // mid-session shrinks would re-trigger the halo.
    property real _surfaceH: 0
    onSurfaceHeightChanged: if (open && surfaceHeight > _surfaceH) _surfaceH = surfaceHeight
    Timer {
        id: _surfaceCollapseTimer
        interval: root.animDuration + 20
        onTriggered: if (!root.open) root._surfaceH = 0
    }
    implicitHeight: _fullscreen ? -1 : _surfaceH

    // Mask follows the visible panel rect so input only lands where the
    // panel is actually painted. In fullscreen mode (closeOnOutsideClick)
    // the click-catcher needs the full surface, so cover everything.
    mask: Region {
        x: root._fullscreen ? 0 : panel.x
        y: root._fullscreen ? 0 : panel.y
        width:  root._fullscreen ? root.width  : panel.width
        height: root._fullscreen ? root.height : panel.height
    }

    // outside-click catcher — sits behind the visible panel, fills the rest
    // of the (now fullscreen) PanelWindow. Declared before `panel` so panel
    // renders on top and absorbs its own clicks.
    MouseArea {
        anchors.fill: parent
        enabled: root._fullscreen
        visible: root._fullscreen
        onClicked: root.requestClose()
    }

    // Hover tracker scoped to the visible panel. Keeping it on `panel`
    // (rather than root) matters in fullscreen mode (`closeOnOutsideClick`):
    // the surface fills the entire screen, so a root-level hover would
    // fire as soon as the cursor entered the surface — i.e. anywhere on
    // screen — and panelLeave would never fire when moving to the desktop.
    // Edge-deadzone hover (ThemeSwitcher) is handled separately by
    // EdgeBumper, so panel-level hover is safe everywhere.
    HoverHandler {
        id: panelHover
        parent: panel
        onHoveredChanged: hovered ? root.panelEnter() : root.panelLeave()
    }

    // -- panel positioning -----------------------------------------------
    // For centered modals the PanelWindow spans the full width, and `panel`
    // is centered inside it at the configured panelTotalWidth. For
    // left/right aligned modals the PanelWindow itself is panelTotalWidth.
    Item {
        id: panel

        anchors.horizontalCenter: root.isCenter ? parent.horizontalCenter : undefined
        anchors.horizontalCenterOffset: root.isCenter ? root.panelXOffset : 0
        anchors.left:  !root.isCenter && root.align === "left"  ? parent.left  : undefined
        anchors.right: !root.isCenter && root.align === "right" ? parent.right : undefined
        anchors.top:    root.edge === "top"    ? parent.top    : undefined
        anchors.bottom: root.edge === "bottom" ? parent.bottom : undefined
        Behavior on anchors.horizontalCenterOffset {
            enabled: root.animatePanelXOffset
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }

        width:  root.panelTotalWidth
        // Inner visible panel height — independent of the PanelWindow's
        // surface height. Always animated so ThemeSwitcher (with constant
        // surfaceHeight) collapses smoothly inside a fixed-size surface
        // and CenterPopouts can morph between launcher (640) and
        // workspaces (~1160) widths.
        height: root.open ? root.contentHeight : 0
        Behavior on width {
            enabled: root.animatePanelWidth
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }

        // Fade only when closing — once the panel shrinks past invRadius*2
        // the inverse-corner curves clamp to near zero and would render as
        // a flat-edged rectangle. Open panels always full opacity (so the
        // ThemeSwitcher's always-on peek strip doesn't dim).
        opacity: root.open ? 1 : Math.min(1, panel.height / (root.invRadius * 2))

        clip: true   // bound Shape overdraw to current panel rect during animation

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
            anchors.leftMargin:  root.leftInverseWidth
            anchors.rightMargin: root.rightInverseWidth
        }
    }

    // -- SVG path construction -------------------------------------------
    // Traverses the perimeter clockwise from TL. For each corner emits a
    // line + (optional) arc based on cornerType; uses safe-radius clamps so
    // very small heights don't produce malformed paths.
    readonly property string _svgPath: {
        var W = panelTotalWidth;
        // bind to panel.height (animated value) not _panelHeight (target),
        // so the shape shrinks together with the panel rect.
        var H = panel.height;
        var R  = Math.min(invRadius,    H / 2);
        var bR = Math.min(cornerRadius, H / 2);

        // Below invRadius the elliptical inverse arc (ry=R) squashes into
        // a near-flat stub that reads as a stray curl rather than a corner.
        // Promote inverse → flush below this threshold so the panel just
        // becomes a clean rectangle at small H (e.g. ThemeSwitcher peek).
        function effCorner(c) { return (c === "inverse" && H < invRadius) ? "flush" : c; }
        var cTL = effCorner(cornerTL);
        var cTR = effCorner(cornerTR);
        var cBR = effCorner(cornerBR);
        var cBL = effCorner(cornerBL);

        // Inverse insets stay anchored at invRadius regardless of H. The
        // arcs become elliptical (rx=invRadius, ry=R) when H clamps R below
        // invRadius — keeps the body's left/right edges from drifting as
        // the panel collapses (e.g. ThemeSwitcher's 8px peek).
        var lI = leftInverseWidth;
        var rI = rightInverseWidth;
        var li = lI;                          // body left x
        var ri = W - rI;                      // body right x

        // y at which adjacent edges meet each corner type
        function topInsetY(c)    { return c === "inverse" ? R : (c === "rounded" ? bR : 0); }
        function bottomInsetY(c) { return c === "inverse" ? H - R : (c === "rounded" ? H - bR : H); }
        function leftInsetX(c)   { return c === "rounded" ? li + bR : li; } // inverse and flush both align with body x
        function rightInsetX(c)  { return c === "rounded" ? ri - bR : ri; }

        var p = "";

        // ---- start at TL (going clockwise) ----
        if (cTL === "rounded") {
            p += "M " + (li + bR) + " 0 ";
        } else if (cTL === "inverse") {
            p += "M 0 0 ";
        } else { // flush
            p += "M " + li + " 0 ";
        }

        // ---- top edge to TR ----
        if (cTR === "rounded") {
            p += "L " + (ri - bR) + " 0 ";
            p += "A " + bR + " " + bR + " 0 0 1 " + ri + " " + bR + " ";
        } else if (cTR === "inverse") {
            p += "L " + W + " 0 ";
            p += "A " + rI + " " + R + " 0 0 0 " + ri + " " + R + " ";
        } else { // flush
            p += "L " + ri + " 0 ";
        }

        // ---- right edge to BR ----
        p += "L " + ri + " " + bottomInsetY(cBR) + " ";
        if (cBR === "rounded") {
            p += "A " + bR + " " + bR + " 0 0 1 " + (ri - bR) + " " + H + " ";
        } else if (cBR === "inverse") {
            p += "A " + rI + " " + R + " 0 0 0 " + W + " " + H + " ";
        }
        // flush: bottom edge will continue from (ri, H)

        // ---- bottom edge to BL ----
        var bottomEndX;
        if (cBL === "rounded") {
            bottomEndX = li + bR;
        } else if (cBL === "inverse") {
            bottomEndX = 0;
        } else { // flush
            bottomEndX = li;
        }
        p += "L " + bottomEndX + " " + H + " ";

        // ---- BL corner ----
        if (cBL === "rounded") {
            p += "A " + bR + " " + bR + " 0 0 1 " + li + " " + (H - bR) + " ";
        } else if (cBL === "inverse") {
            p += "A " + lI + " " + R + " 0 0 0 " + li + " " + (H - R) + " ";
        }

        // ---- left edge to TL ----
        p += "L " + li + " " + topInsetY(cTL) + " ";

        // ---- TL corner closing ----
        if (cTL === "rounded") {
            p += "A " + bR + " " + bR + " 0 0 1 " + (li + bR) + " 0 ";
        } else if (cTL === "inverse") {
            p += "A " + lI + " " + R + " 0 0 0 0 0 ";
        }

        p += "Z";
        return p;
    }
}
