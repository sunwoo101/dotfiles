// CenterPopouts — single Modal that hosts both AppLauncherContent and
// WorkspacesContent and morphs between them, exactly like Popouts.qml does
// for left/right side popouts. The wrapper is hover-driven via shellRoot's
// centerCurrent / centerOwner state — no closeOnOutsideClick (hover-leave
// closes the popout, mirroring every other bar popout).

import QtQuick
import Quickshell
import Quickshell.Wayland

Modal {
    id: root

    edge:  "top"
    align: "center"
    cornerRadius: 16

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    // current popout name: "launcher" | "workspaces" | ""
    required property string current
    // True when the popout was summoned via IPC (keybind), false when
    // hover-opened. Drives the click-outside + keyboard-focus behavior:
    // hover-opened uses OnDemand focus (avoids the icon-flash) and no
    // outside-click catcher; IPC-opened uses Exclusive focus and the
    // catcher so Escape and click-outside both close.
    required property bool ipcManaged
    // workspace-thumb props passed straight through to WorkspacesContent
    required property string thumbDir
    required property int thumbVersion

    open: current !== ""
    closeOnOutsideClick: current === "launcher" && ipcManaged
    contentWidth: current === "launcher"
        ? (launcherLoader.item ? launcherLoader.item.implicitWidth  : 0)
        : current === "workspaces"
            ? (workspacesLoader.item ? workspacesLoader.item.implicitWidth  : 0)
            : 0
    contentHeight: current === "launcher"
        ? (launcherLoader.item ? launcherLoader.item.implicitHeight : 0)
        : current === "workspaces"
            ? (workspacesLoader.item ? workspacesLoader.item.implicitHeight : 0)
            : 0

    // Keyboard focus only when launcher is the active content.
    //   IPC-opened (ipcManaged=true): Exclusive — Escape keypress reaches
    //     the search input reliably. Cursor isn't on the launcher icon
    //     in this mode, so the bar-hover-flash doesn't trigger.
    //   Hover-opened (ipcManaged=false): OnDemand — avoids the flash
    //     that Exclusive caused (Hyprland redirected pointer focus too,
    //     making the bar icon's MouseArea fire onExited every ~250 ms).
    //     Typing still works because TextInput.forceActiveFocus() routes
    //     keyboard through OnDemand.
    WlrLayershell.keyboardFocus: {
        if (current !== "launcher") return WlrLayershell.None;
        return ipcManaged ? WlrLayershell.Exclusive : WlrLayershell.OnDemand;
    }

    onCurrentChanged: {
        if (current === "launcher" && launcherLoader.item) {
            launcherLoader.item.focusSearch();
        }
    }

    Loader {
        id: launcherLoader
        anchors.fill: parent
        active: true
        opacity: root.current === "launcher" ? 1 : 0
        enabled: root.current === "launcher"
        z: root.current === "launcher" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
        sourceComponent: AppLauncherContent {
            cFg: root.cFg
            cPrimary: root.cPrimary
            cMuted: root.cMuted
            fontFamily: root.fontFamily
            onRequestClose: root.requestClose()
        }
    }

    Loader {
        id: workspacesLoader
        anchors.fill: parent
        active: true
        opacity: root.current === "workspaces" ? 1 : 0
        enabled: root.current === "workspaces"
        z: root.current === "workspaces" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
        sourceComponent: WorkspacesContent {
            cBg: root.cBg
            cFg: root.cFg
            cPrimary: root.cPrimary
            cMuted: root.cMuted
            fontFamily: root.fontFamily
            thumbDir: root.thumbDir
            thumbVersion: root.thumbVersion
            onRequestClose: root.requestClose()
        }
    }
}
