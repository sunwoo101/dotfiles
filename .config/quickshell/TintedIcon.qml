// TintedIcon — symbolic SVG from Colloid-Dark, recolored via MultiEffect.
// We bypass Quickshell.Widgets.IconImage and use a direct file:// path so
// the resolution is unambiguous (the symbolic SVGs use currentColor with a
// fallback CSS color of #dedede; rendered as-is by Qt = light gray).

import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: root
    required property string name
    required property color tint
    property int size: 16
    property string iconBase: Quickshell.env("HOME")
        + "/.local/share/icons/Colloid-Dark/status/symbolic/"

    implicitWidth: size
    implicitHeight: size

    Image {
        id: src
        source: "file://" + root.iconBase + root.name + ".svg"
        sourceSize.width: root.size
        sourceSize.height: root.size
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        layer.enabled: true
        visible: false
        onStatusChanged: {
            if (status === Image.Error)
                console.log("TintedIcon load FAILED:", source);
        }
    }
    MultiEffect {
        anchors.fill: src
        source: src
        colorizationColor: root.tint
        colorization: 1.0
        brightness: 0.5
    }
}
