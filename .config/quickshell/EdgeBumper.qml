// EdgeBumper — invisible hover trigger anchored to a screen edge. Acts as
// the "icon" that triggers a non-bar Modal to expand, analogous to how bar
// icons trigger popouts.
//
// Bleeds 1 px past the screen edge (margins.{edge}: -1) so the cursor at
// the screen-edge row sits inside the bumper's surface, not at its
// boundary — avoids Wayland's pointer-leave at the absolute last pixel row
// (which would close the modal mid-open). The bumper is invisible, so the
// 1 px overflow has nothing to clip.
//
// Usage in shell.qml — pair with the modal's Variants block:
//
//   Variants {
//       model: _screensWhenReady
//       FooModal {
//           modelData: modelData
//           externalHovered: shellRoot._bumperHovered("foo", modelData.name)
//       }
//   }
//   Variants {
//       model: _screensWhenReady
//       EdgeBumper {
//           modelData: modelData
//           edge: "bottom"
//           hitWidth: 596         // = FooModal.panelTotalWidth
//           onBumperEnter: shellRoot._setBumperHover("foo", modelData.name, true)
//           onBumperLeave: shellRoot._setBumperHover("foo", modelData.name, false)
//       }
//   }

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bumper

    required property var modelData
    property string edge: "bottom"   // "top" | "bottom"
    property int hitWidth:  200
    property int hitHeight: 8

    signal bumperEnter()
    signal bumperLeave()

    screen: modelData
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayershell.Overlay

    anchors {
        top:    edge === "top"
        bottom: edge === "bottom"
        left:   true
        right:  true
    }
    implicitHeight: hitHeight
    margins.top:    edge === "top"    ? -1 : 0
    margins.bottom: edge === "bottom" ? -1 : 0

    // mask only the centered hitWidth slice — outside that, input passes
    // through to whatever's below. Height extends 1 px past the surface
    // edge to cover the off-screen overflow row.
    mask: Region {
        x: (bumper.width - hitWidth) / 2
        y: 0
        width:  hitWidth
        height: hitHeight + 1
    }

    HoverHandler {
        onHoveredChanged: hovered ? bumper.bumperEnter() : bumper.bumperLeave()
    }
}
