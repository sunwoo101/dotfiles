// TintedIcon — symbolic SVG recolored via MultiEffect. By default resolves
// the name through the active icon theme (honors inheritance — e.g.
// Colloid-Dark → Adwaita), so callers can use any standard freedesktop
// symbolic name. For icons that aren't in any installed theme, set
// `iconBase` to a directory and `name` is treated as `<iconBase>/<name>.svg`.

import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: root
    required property string name
    required property color tint
    property int size: 16
    // direct-path mode — when set, look up <iconBase>/<name>.svg instead
    // of going through Quickshell.iconPath (theme-resolved).
    property string iconBase: ""

    implicitWidth: size
    implicitHeight: size

    readonly property string _resolvedSource: {
        if (!name) return "";
        if (iconBase) return "file://" + iconBase + name + ".svg";
        var p = Quickshell.iconPath(name);
        return p || "";
    }

    Image {
        id: src
        source: root._resolvedSource
        sourceSize.width: root.size
        sourceSize.height: root.size
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        layer.enabled: true
        visible: false
        onStatusChanged: {
            if (status === Image.Error)
                console.log("TintedIcon load FAILED:", root.name, "→", source);
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
