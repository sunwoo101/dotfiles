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
// Usage in shell.qml — pair with EdgePopouts (depth-counter pattern, so
// cursor handoff between bumper and panel doesn't drop the panel):
//
//   Variants {
//       model: _screensWhenReady
//       EdgePopouts {
//           ...
//           current: shellRoot.bottomOwner === modelData.name ? shellRoot.bottomCurrent : ""
//           onPanelEnter: shellRoot.bottomEnter("foo", modelData.name)
//           onPanelLeave: shellRoot.bottomLeave()
//       }
//   }
//   Variants {
//       model: _screensWhenReady
//       EdgeBumper {
//           modelData: modelData
//           edge: "bottom"
//           hitWidth: 596         // matches the content's panel total width
//           onBumperEnter: shellRoot.bottomEnter("foo", modelData.name)
//           onBumperLeave: shellRoot.bottomLeave()
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
    // Horizontal placement of the hit region. Default is centered; set
    // to a screen-x to anchor the hit zone off-center (e.g. for a
    // bottom-left bumper paired with an align: "left" Modal).
    property real hitX: (width - hitWidth) / 2

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
        x: bumper.hitX
        y: 0
        width:  hitWidth
        height: hitHeight + 1
    }

    HoverHandler {
        onHoveredChanged: hovered ? bumper.bumperEnter() : bumper.bumperLeave()
    }
}
