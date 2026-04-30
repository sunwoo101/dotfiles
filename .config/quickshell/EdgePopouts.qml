// EdgePopouts — generic Modal wrapper that hosts multiple swappable
// content items at the top OR bottom edge, center-aligned. Mirrors the
// Popouts wrapper for left/right side popouts but here the contents are
// caller-supplied via a `contents` model.
//
// Two modes:
//   1. peekHeight == 0 (default): fully closed when current === ""; opens
//      from closed by snapping width to the active content's size and
//      animating only height (ThemeSwitcher-style vertical reveal).
//      Switching between contents while open morphs both axes.
//   2. peekHeight  > 0: panel is always mounted at peekHeight as a thin
//      sliver; current === "" collapses to that strip rather than fully
//      unmounting. peekDefault names the content whose width drives the
//      strip width before any content is summoned.
//
// Usage:
//   EdgePopouts {
//       edge: "top"        // or "bottom"
//       current: shellRoot.centerCurrent
//       contents: [
//           { name: "launcher",   source: launcherComp },
//           { name: "workspaces", source: workspacesComp },
//       ]
//   }
//   Component { id: launcherComp; AppLauncherContent { ... } }
//
// Each content is a plain Item with implicitWidth/implicitHeight (no
// PanelWindow). Content components are declared in the caller's scope so
// they can lexically capture shellRoot for prop wiring.

import QtQuick
import Quickshell
import Quickshell.Wayland

Modal {
    id: root

    align: "center"
    cornerRadius: 16

    // Caller-supplied list of available popouts.
    // [{ name: <string>, source: <Component>, xOffset: <real> }, ...]
    // xOffset is horizontal pixels from screen center (negative = left).
    // Defaults to 0 (centered). Wrapper morphs panel position between
    // contents on switch, the same way it morphs width and height.
    property var contents: []

    // Active popout name; "" means "no active content".
    required property string current

    // Peek mode. 0 = no peek (full close on current === ""); >0 = always
    // mounted at peekHeight px when nothing is active.
    property int peekHeight: 0
    // When peekHeight > 0, this names the content whose loader provides
    // the resting (collapsed) width. The peek strip is rendered at that
    // width so it visually matches the default content's panel.
    property string peekDefault: ""

    // Launcher-style: when this matches `current` AND ipcManaged is true,
    // expand to fullscreen with click-catcher and Exclusive keyboard focus.
    property string ipcContentName: ""
    property bool ipcManaged: false

    // workspace-thumb props passed straight through to a "workspaces"
    // entry (legacy carry-over so shell.qml doesn't have to thread them
    // through a Component-scope hop). Other content types ignore these.
    property string thumbDir: ""
    property int thumbVersion: 0

    // Bumper-driven hover passthrough (mirrors what ThemeSwitcher used to
    // do directly). Setting this to true emits a synthetic panelEnter so
    // the same close-timer / hover-source logic fires as for cursor-on-
    // panel hover.
    property bool externalHovered: false
    onExternalHoveredChanged: externalHovered ? panelEnter() : panelLeave()

    // Emitted whenever `current` becomes a non-empty value. Callers
    // connect from inside a content's Component to react (e.g. the
    // launcher grabbing keyboard focus on its search input).
    signal contentActivated(string name)

    open: peekHeight > 0 || current !== ""
    closeOnOutsideClick: ipcManaged && current === ipcContentName

    contentWidth:  _stickyWidth
    contentHeight: (peekHeight > 0 && current === "") ? peekHeight : _stickyHeight
    panelXOffset:  _stickyXOffset

    // Sticky values — driven imperatively in onCurrentChanged below (and
    // by live loader resize signals). Held during close so the peek
    // strip stays at the last-shown content's position+width.
    property int _stickyWidth: 480
    property int _stickyHeight: 200
    property real _stickyXOffset: 0
    property string _prevCurrent: ""

    function _xOffsetForName(name) {
        for (var i = 0; i < contents.length; i++) {
            if (contents[i].name === name) {
                return contents[i].xOffset || 0;
            }
        }
        return 0;
    }

    // Per-name Loader registry, populated as Repeater delegates instantiate.
    property var _loaderByName: ({})

    function _registerLoader(name, loader) {
        var m = Object.assign({}, _loaderByName);
        m[name] = loader;
        _loaderByName = m;
        // First-load: if this loader is for peekDefault and we're idle,
        // adopt its size and xOffset so the peek strip matches the
        // default content. Also captures initial values when current is
        // already set at startup.
        if (loader && loader.item) {
            if (root.current === name) {
                root._stickyWidth   = loader.item.implicitWidth;
                root._stickyHeight  = loader.item.implicitHeight;
                root._stickyXOffset = root._xOffsetForName(name);
            } else if (root.peekDefault === name && root.current === "") {
                root._stickyWidth   = loader.item.implicitWidth;
                root._stickyHeight  = loader.item.implicitHeight;
                root._stickyXOffset = root._xOffsetForName(name);
            }
        }
    }

    onCurrentChanged: {
        var prev = _prevCurrent;
        _prevCurrent = current;

        // Closing — leave _stickyWidth/_stickyHeight at their last values
        // so panel.width stays pinned and only height collapses (to 0 in
        // full-close mode, or to peekHeight in peek mode via the
        // contentHeight binding above).
        if (current === "") return;

        var loader = _loaderByName[current];
        if (!loader || !loader.item) return;

        var newW = loader.item.implicitWidth;
        var newH = loader.item.implicitHeight;
        var newX = _xOffsetForName(current);

        if (prev === "" && peekHeight === 0) {
            // Full-close mode opening from closed: snap width and xOffset
            // without animating; only height animates from 0 → newH.
            animatePanelWidth = false;
            animatePanelXOffset = false;
            _stickyWidth   = newW;
            _stickyHeight  = newH;
            _stickyXOffset = newX;
            animatePanelWidth = true;
            animatePanelXOffset = true;
        } else {
            // Peek-to-active or switching between two active contents —
            // full wrapper morph (width, height, xOffset all animate).
            _stickyWidth   = newW;
            _stickyHeight  = newH;
            _stickyXOffset = newX;
        }

        contentActivated(current);
    }

    // Keyboard focus — Exclusive when an IPC-summoned content is active,
    // OnDemand when it's hover-summoned, None otherwise. Generalizes the
    // previous launcher-specific path: callers supply ipcContentName.
    WlrLayershell.keyboardFocus: {
        if (current !== ipcContentName || ipcContentName === "") return WlrLayershell.None;
        return ipcManaged ? WlrLayershell.Exclusive : WlrLayershell.OnDemand;
    }

    Repeater {
        model: root.contents

        Loader {
            id: contentLoader
            required property var modelData

            anchors.fill: parent
            active: true
            opacity: root.current === modelData.name ? 1 : 0
            // Disable input when not active — clicks would otherwise pass
            // through visible content to whichever Loader sits behind.
            // Required for invisible buttons under z-stacked Loaders.
            enabled: root.current === modelData.name
            // Active Loader z-topmost so HoverHandler/MouseArea descendants
            // receive hover events (Qt6/Wayland: hover doesn't propagate
            // through disabled siblings, click does).
            z: root.current === modelData.name ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
            }

            sourceComponent: modelData.source
            onLoaded: root._registerLoader(modelData.name, this)

            // Live size tracking — picks up content resize while the
            // popout is active (e.g. workspaces overview gaining thumbs).
            Connections {
                target: contentLoader.item
                ignoreUnknownSignals: true
                function onImplicitWidthChanged() {
                    if (root.current === contentLoader.modelData.name) {
                        root._stickyWidth = contentLoader.item.implicitWidth;
                    }
                }
                function onImplicitHeightChanged() {
                    if (root.current === contentLoader.modelData.name) {
                        root._stickyHeight = contentLoader.item.implicitHeight;
                    }
                }
            }
        }
    }
}
