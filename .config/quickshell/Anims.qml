pragma Singleton
import QtQuick

QtObject {
    property real multiplier: 1.0

    readonly property int panel:  Math.round(280 * multiplier)
    readonly property int pill:   Math.round(240 * multiplier)
    readonly property int accent: Math.round(140 * multiplier)
    readonly property int micro:  Math.round(120 * multiplier)
    readonly property int pulse:  Math.round(800 * multiplier)
}
