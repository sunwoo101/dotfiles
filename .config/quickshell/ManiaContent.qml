// ManiaContent — osu!mania-style 4-key falling-note game.
//
// Notes (rectangles) fall in 4 columns; press D / F / J / K when a note's
// center crosses the judgment line. Timing-based scoring with combo
// multiplier. Same resource-gating + score-reset model as
// MinigameContent: gameplay subtree lives in a Loader gated on `active`,
// score zeroed every reload via the gameplay Item's onCompleted.
//
// Keyboard input requires the wrapper EdgePopouts to set
// `kbdFocusName: "mania"` so the layer-shell surface gets kbd focus
// while the game is open.

import QtQuick

Item {
    id: root

    implicitWidth:  560
    implicitHeight: 640

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    required property real panelVisibleHeight
    required property real peekHeight
    required property bool active

    property int score: 0
    property int combo: 0

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
            text: "Press D F J K"
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
            focus: true

            readonly property int  columnCount:    4
            readonly property var  keyCodes:  [Qt.Key_D, Qt.Key_F, Qt.Key_J, Qt.Key_K]
            readonly property var  keyLabels: ["D", "F", "J", "K"]
            readonly property real columnWidth:    width / columnCount
            readonly property real noteHeight:     16
            readonly property int  fallDurationMs: 800
            readonly property real keyPadHeight:   26
            readonly property real keyPadGap:      4
            // Y at which note center should align for a Perfect hit.
            readonly property real judgmentLineY:  height - keyPadHeight - keyPadGap
            readonly property int  spawnIntervalMs: 200

            // Hit-window thresholds in pixels (note-center distance from
            // judgment line). Smaller = stricter. Tuned for fallDurationMs
            // = 1500: each px ≈ 1500 / (height + noteHeight) ms ≈ 7 ms.
            readonly property real perfectWindow: 8
            readonly property real greatWindow:   18
            readonly property real goodWindow:    32

            property var liveNotes: []
            property var keyPads:   []

            Component.onCompleted: {
                root.score = 0;
                root.combo = 0;
                forceActiveFocus();
            }

            Keys.onPressed: function(event) {
                for (var i = 0; i < game.columnCount; i++) {
                    if (event.key === game.keyCodes[i]) {
                        game.tryHitColumn(i);
                        event.accepted = true;
                        return;
                    }
                }
            }

            // -- column dividers --------------------------------------
            Repeater {
                model: game.columnCount - 1
                Rectangle {
                    required property int index
                    x: (index + 1) * game.columnWidth - 0.5
                    y: 0
                    width: 1
                    height: game.height
                    color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                }
            }

            // -- judgment line ---------------------------------------
            Rectangle {
                x: 0
                y: game.judgmentLineY
                width: game.width
                height: 2
                color: root.cPrimary
                opacity: 0.7
            }

            // -- key pads --------------------------------------------
            Repeater {
                model: game.columnCount

                Rectangle {
                    id: pad
                    required property int index

                    x: pad.index * game.columnWidth + 4
                    y: game.judgmentLineY + game.keyPadGap
                    width:  game.columnWidth - 8
                    height: game.keyPadHeight
                    radius: 4

                    property bool pressed: false
                    color: pressed
                        ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.45)
                        : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                    Behavior on color { ColorAnimation { duration: 80 } }

                    border.color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.20)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: game.keyLabels[pad.index]
                        color: root.cFg
                        font.pixelSize: 13
                        font.family: root.fontFamily
                        font.bold: true
                    }

                    Timer {
                        id: padReleaseTimer
                        interval: 100
                        onTriggered: pad.pressed = false
                    }

                    function flash() {
                        pad.pressed = true;
                        padReleaseTimer.restart();
                    }

                    Component.onCompleted: game.keyPads.push(pad)
                }
            }

            // -- note factory ----------------------------------------
            Component {
                id: noteComp
                Rectangle {
                    id: note
                    required property int columnIndex
                    property bool dead: false

                    x: columnIndex * game.columnWidth + 4
                    width:  game.columnWidth - 8
                    height: game.noteHeight
                    radius: 3
                    color: root.cPrimary

                    NumberAnimation on y {
                        from: -note.height
                        to:   game.height
                        duration: game.fallDurationMs
                        running: !note.dead
                        onFinished: {
                            if (note.dead) return;
                            note.dead = true;
                            game.judge(0, columnIndex, true, -1);
                            note.destroy();
                        }
                    }

                    Component.onCompleted: game.liveNotes.push(note)
                    Component.onDestruction: {
                        var arr = game.liveNotes;
                        var idx = arr.indexOf(note);
                        if (idx >= 0) arr.splice(idx, 1);
                        game.liveNotes = arr;
                    }
                }
            }

            // -- floating judgment label -----------------------------
            Component {
                id: indicatorComp
                Text {
                    id: indicator
                    required property real targetX
                    required property string label
                    required property color tint

                    x: targetX - implicitWidth / 2
                    y: game.judgmentLineY - 24
                    text: label
                    color: tint
                    font.pixelSize: 15
                    font.family: root.fontFamily
                    font.bold: true

                    Component.onCompleted: floatAnim.start()
                    ParallelAnimation {
                        id: floatAnim
                        NumberAnimation {
                            target: indicator; property: "y"
                            to: indicator.y - 24
                            duration: 500
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: indicator; property: "opacity"
                            to: 0
                            duration: 500
                        }
                        onFinished: indicator.destroy()
                    }
                }
            }

            // -- spawn -----------------------------------------------
            Timer {
                id: spawnTimer
                interval: game.spawnIntervalMs
                repeat: true
                running: true
                onTriggered: {
                    if (game.width <= 0) return;
                    var col = Math.floor(Math.random() * game.columnCount);
                    noteComp.createObject(game, { columnIndex: col });
                }
            }

            // -- input → hit ----------------------------------------
            // Pick the closest live note in this column to the judgment
            // line. Stray keypresses (no nearby note) flash the pad but
            // do not break combo or fire a Miss indicator (osu!mania
            // standard rules treat note-less keypresses as no-op).
            function tryHitColumn(col) {
                if (col < keyPads.length && keyPads[col]) {
                    keyPads[col].flash();
                }

                var bestNote = null;
                var bestDist = Infinity;
                for (var i = 0; i < liveNotes.length; i++) {
                    var n = liveNotes[i];
                    if (!n || n.dead || n.columnIndex !== col) continue;
                    var center = n.y + game.noteHeight / 2;
                    var d = Math.abs(center - game.judgmentLineY);
                    if (d < bestDist) {
                        bestDist = d;
                        bestNote = n;
                    }
                }

                if (!bestNote) return;
                if (bestDist > goodWindow) return;

                bestNote.dead = true;
                var x = bestNote.x + bestNote.width / 2;
                game.judge(bestDist, col, false, x);
                bestNote.destroy();
            }

            function judge(dist, col, expired, indicatorX) {
                var label, tint, base;
                if (expired || dist > goodWindow) {
                    label = "Miss";    tint = root.cMuted;   base = 0;
                } else if (dist < perfectWindow) {
                    label = "Perfect!"; tint = root.cPrimary; base = 300;
                } else if (dist < greatWindow) {
                    label = "Great";    tint = root.cFg;      base = 100;
                } else {
                    label = "Good";     tint = root.cMuted;   base = 50;
                }

                if (base === 0) {
                    root.combo = 0;
                } else {
                    root.combo += 1;
                    var mult = 1 + (root.combo - 1) * 0.05;
                    root.score += Math.round(base * mult);
                }

                var x = indicatorX > 0
                    ? indicatorX
                    : (col * game.columnWidth + game.columnWidth / 2);
                indicatorComp.createObject(game, {
                    targetX: x, label: label, tint: tint
                });
            }
        }
    }
}
