// MinigameContent — tiny osu-style rhythm game.
//
// Hit circles spawn at non-overlapping random positions; an approach
// circle shrinks toward the hit circle. Click as the approach circle
// meets the hit circle for max points. Click timing is judged Perfect /
// Great / Good / Miss (Miss also fires on no-click timeout).
//
// Resource gating: the gameplay subtree lives in a `Loader` whose
// `active` flag tracks the wrapper's open state — collapsed → Loader
// unloads, killing every Timer and NumberAnimation. Score resets on
// every reopen via the gameplay Item's `Component.onCompleted`.

import QtQuick

Item {
    id: root

    implicitWidth:  560
    implicitHeight: 320

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    // From the wrapper — drives the peek-fade ratio.
    required property real panelVisibleHeight
    required property real peekHeight

    // True when the window is fully open (driven from shell.qml). Gates
    // the gameplay Loader so timers/animations only exist while playing.
    required property bool active

    // Score lives on root so the header stays bound across Loader
    // unload/reload, but the gameComponent's Item.Component.onCompleted
    // resets these every time the Loader instantiates a fresh game (i.e.
    // every reopen).
    property int score: 0
    property int combo: 0

    // -- header (title + score) --------------------------------------
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 14
        height: 24

        opacity: Math.max(0,
            (root.panelVisibleHeight - root.peekHeight)
            / (root.implicitHeight - root.peekHeight))

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "Click the Circles"
            color: root.cFg
            font.pixelSize: 17
            font.family: root.fontFamily
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "Score: " + root.score
                + (root.combo > 1 ? "   ×" + root.combo : "")
            color: root.cFg
            font.pixelSize: 14
            font.family: root.fontFamily
        }
    }

    // -- gameplay area ------------------------------------------------
    Loader {
        id: gameLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        opacity: header.opacity
        active: root.active
        sourceComponent: gameComponent
    }

    Component {
        id: gameComponent

        Item {
            id: game
            anchors.fill: parent
            clip: true

            readonly property real hitRadius:           22
            readonly property real approachStartRadius: 56
            readonly property int  approachDurationMs:  800
            readonly property int  spawnIntervalMs:     500

            // Hit-window thresholds (|1 - lifetime|). Smaller = stricter.
            readonly property real perfectWindow: 0.08
            readonly property real greatWindow:   0.18
            readonly property real goodWindow:    0.32

            // Live circle list — used for overlap rejection. Manually
            // tracked rather than scanning game.children because that
            // includes Timers / Components / indicator labels.
            property var liveCircles: []

            Component.onCompleted: {
                root.score = 0;
                root.combo = 0;
            }

            // -- circle factory --------------------------------------
            Component {
                id: circleComp

                Item {
                    id: circle

                    required property real spawnX
                    required property real spawnY

                    property real lifetime: 0
                    property bool dead: false

                    x: spawnX - game.approachStartRadius
                    y: spawnY - game.approachStartRadius
                    width:  game.approachStartRadius * 2
                    height: width

                    Component.onCompleted: game.liveCircles.push(circle)
                    Component.onDestruction: {
                        var arr = game.liveCircles;
                        var idx = arr.indexOf(circle);
                        if (idx >= 0) arr.splice(idx, 1);
                        game.liveCircles = arr;
                    }

                    Rectangle {  // hit circle (static)
                        anchors.centerIn: parent
                        width:  game.hitRadius * 2
                        height: width
                        radius: width / 2
                        color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.18)
                        border.color: root.cPrimary
                        border.width: 3
                    }
                    Rectangle {  // approach circle (shrinks)
                        anchors.centerIn: parent
                        readonly property real r: game.approachStartRadius
                            + (game.hitRadius - game.approachStartRadius) * circle.lifetime
                        width:  r * 2
                        height: r * 2
                        radius: r
                        color: "transparent"
                        border.color: root.cFg
                        border.width: 2
                        opacity: 1 - circle.lifetime * 0.4
                    }

                    NumberAnimation on lifetime {
                        from: 0; to: 1
                        duration: game.approachDurationMs
                        running: !circle.dead
                        onFinished: {
                            if (circle.dead) return;
                            circle.dead = true;
                            game.judge(circle.lifetime, circle.spawnX, circle.spawnY, true);
                            circle.destroy();
                        }
                    }

                    MouseArea {
                        anchors.centerIn: parent
                        width:  (game.hitRadius + 8) * 2
                        height: width
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            if (circle.dead) return;
                            circle.dead = true;
                            game.judge(circle.lifetime, circle.spawnX, circle.spawnY, false);
                            circle.destroy();
                        }
                    }
                }
            }

            // -- floating judgment label -----------------------------
            Component {
                id: indicatorComp

                Text {
                    id: indicator
                    required property real targetX
                    required property real targetY
                    required property string label
                    required property color tint

                    x: targetX - implicitWidth  / 2
                    y: targetY - implicitHeight / 2
                    text: label
                    color: tint
                    font.pixelSize: 18
                    font.family: root.fontFamily
                    font.bold: true

                    Component.onCompleted: floatAnim.start()
                    ParallelAnimation {
                        id: floatAnim
                        NumberAnimation {
                            target: indicator; property: "y"
                            to: indicator.y - 32
                            duration: 600
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: indicator; property: "opacity"
                            to: 0
                            duration: 600
                        }
                        onFinished: indicator.destroy()
                    }
                }
            }

            // -- judgment ---------------------------------------------
            // judge(lifetime, x, y, expired): scores the hit, breaks or
            // bumps combo, spawns an indicator. `expired = true` means
            // the approach circle ran out (always Miss).
            function judge(lifetime, x, y, expired) {
                var dist = Math.abs(1 - lifetime);
                var label, tint, base;
                if (expired || dist > goodWindow) {
                    label = "Miss";
                    tint = root.cMuted;
                    base = 0;
                } else if (dist < perfectWindow) {
                    label = "Perfect!";
                    tint = root.cPrimary;
                    base = 300;
                } else if (dist < greatWindow) {
                    label = "Great";
                    tint = root.cFg;
                    base = 100;
                } else {
                    label = "Good";
                    tint = root.cMuted;
                    base = 50;
                }

                if (base === 0) {
                    root.combo = 0;
                } else {
                    root.combo += 1;
                    // osu-style combo bonus: each hit's points scale
                    // with the running combo. multiplier = 1 + (combo-1) × 0.05.
                    var mult = 1 + (root.combo - 1) * 0.05;
                    root.score += Math.round(base * mult);
                }

                indicatorComp.createObject(game, {
                    targetX: x, targetY: y, label: label, tint: tint
                });
            }

            // -- spawn -------------------------------------------------
            Timer {
                id: spawnTimer
                interval: game.spawnIntervalMs
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: game.spawnCircle()
            }

            function spawnCircle() {
                if (game.width <= 0 || game.height <= 0) return;
                var pad = approachStartRadius + 4;
                var maxX = game.width  - pad;
                var maxY = game.height - pad;
                if (maxX <= pad || maxY <= pad) return;

                // Reject candidate positions that overlap any live circle.
                // Two circles overlap when their center distance is less
                // than 2 × hit-circle radius + a small visual gap.
                var minDist = hitRadius * 2 + 8;
                var minSqr = minDist * minDist;

                for (var attempt = 0; attempt < 25; attempt++) {
                    var x = pad + Math.random() * (maxX - pad);
                    var y = pad + Math.random() * (maxY - pad);
                    var clear = true;
                    for (var i = 0; i < game.liveCircles.length; i++) {
                        var c = game.liveCircles[i];
                        if (!c || c.dead) continue;
                        var dx = c.spawnX - x;
                        var dy = c.spawnY - y;
                        if (dx * dx + dy * dy < minSqr) {
                            clear = false;
                            break;
                        }
                    }
                    if (clear) {
                        circleComp.createObject(game, { spawnX: x, spawnY: y });
                        return;
                    }
                }
                // No space — skip this tick.
            }
        }
    }
}
