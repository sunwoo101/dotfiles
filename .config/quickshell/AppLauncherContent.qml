// AppLauncherContent — content-only (no PanelWindow). Hosted inside the
// CenterPopouts wrapper so the launcher and workspaces overview share a
// single morphing window. Exposes focusSearch() so the wrapper can grab
// keyboard focus on the search input when the launcher becomes active.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: root

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    signal requestClose()

    readonly property int contentWidth:  640
    readonly property int contentHeight: 520
    readonly property int padding:        16

    implicitWidth:  contentWidth
    implicitHeight: contentHeight

    // -- frecency: launch count + last-use timestamp per .desktop id ---------
    // Persisted to ~/.cache/quickshell/launcher-frecency.json. Empty-query
    // ordering is pure frecency; query results add a frecency boost on top of
    // the fuzzy score so familiar apps win on ties.
    property var frecencyData: ({})

    FileView {
        id: frecencyFile
        path: Quickshell.env("HOME") + "/.cache/quickshell/launcher-frecency.json"
        onLoaded: {
            try { root.frecencyData = JSON.parse(text()) || {}; }
            catch (e) { root.frecencyData = {}; }
        }
    }
    Process {
        id: initFrecency
        running: true
        command: ["sh", "-c",
            "mkdir -p ~/.cache/quickshell && [ -f ~/.cache/quickshell/launcher-frecency.json ] || echo '{}' > ~/.cache/quickshell/launcher-frecency.json"]
        onExited: frecencyFile.reload()
    }
    Process { id: saveFrecency }

    function _persistFrecency() {
        var b64 = Qt.btoa(JSON.stringify(root.frecencyData));
        saveFrecency.command = ["sh", "-c",
            "mkdir -p ~/.cache/quickshell && echo '" + b64
            + "' | base64 -d > ~/.cache/quickshell/launcher-frecency.json.tmp"
            + " && mv ~/.cache/quickshell/launcher-frecency.json.tmp ~/.cache/quickshell/launcher-frecency.json"];
        saveFrecency.running = true;
    }
    function _bump(app) {
        if (!app || !app.id) return;
        var d = root.frecencyData[app.id] || { count: 0, lastUsed: 0 };
        d.count = (d.count || 0) + 1;
        d.lastUsed = Date.now();
        var copy = Object.assign({}, root.frecencyData);
        copy[app.id] = d;
        root.frecencyData = copy;
        _persistFrecency();
    }
    function _frecencyScore(app) {
        var d = root.frecencyData[app.id];
        if (!d) return 0;
        var ageDays = (Date.now() - (d.lastUsed || 0)) / 86400000;
        return (d.count || 0) / (1 + ageDays / 7);
    }

    // -- fuzzy match: subsequence with consecutive + word-boundary bonuses --
    // Returns -1 if `q` is not a subsequence of `t`. Higher = better. Exact
    // prefix > substring > scattered subsequence.
    function _fuzzy(q, t) {
        if (!q) return 0;
        if (!t) return -1;
        if (t.startsWith(q)) return 2000 - (t.length - q.length);
        var idx = t.indexOf(q);
        if (idx !== -1) return 1000 - idx * 2 - (t.length - q.length) * 0.1;
        var qi = 0, score = 0, prev = -2, consec = 0;
        for (var i = 0; i < t.length && qi < q.length; i++) {
            if (t.charCodeAt(i) === q.charCodeAt(qi)) {
                score += 10;
                if (i === prev + 1) { consec++; score += consec * 6; }
                else { consec = 0; }
                var pc = i > 0 ? t.charAt(i - 1) : "";
                if (i === 0 || pc === " " || pc === "-" || pc === "_"
                    || pc === "." || pc === "/")
                    score += 12;
                prev = i;
                qi++;
            }
        }
        if (qi < q.length) return -1;
        return score - t.length * 0.05;
    }
    function _appScore(app, query) {
        var rawExec = (app.command && app.command[0])
            || (app.exec || "").split(" ")[0] || "";
        var bin = rawExec.split("/").pop().toLowerCase();
        // Subseq fuzzy only on name + exec basename. Long descriptive fields
        // (genericName / keywords / comment) trip on short abbreviations like
        // "nvide" → "Non-linear Video Editor"; restricting them to substring
        // contains prevents the noisy long tail.
        var best = -1;
        var primary = [(app.name || "").toLowerCase(), bin];
        var weights = [1.0, 0.7];
        for (var i = 0; i < primary.length; i++) {
            var s = root._fuzzy(query, primary[i]);
            if (s < 0) continue;
            var w = s * weights[i];
            if (w > best) best = w;
        }
        var secondary = [
            (app.genericName || "").toLowerCase(),
            (app.keywords || []).join(" ").toLowerCase(),
            (app.comment || "").toLowerCase()
        ];
        var secScores = [40, 30, 20];
        for (var j = 0; j < secondary.length; j++) {
            if (secondary[j] && secondary[j].indexOf(query) !== -1
                && secScores[j] > best)
                best = secScores[j];
        }
        return best;
    }

    function _categoryIcon(cats) {
        if (!cats) return "";
        for (var i = 0; i < cats.length; i++) {
            switch (cats[i]) {
                case "Game":         return "applications-games";
                case "Development":  return "applications-development";
                case "AudioVideo":
                case "Audio":
                case "Video":        return "applications-multimedia";
                case "Office":       return "applications-office";
                case "Network":      return "applications-internet";
                case "Graphics":     return "applications-graphics";
                case "System":
                case "Settings":     return "applications-system";
                case "Utility":      return "applications-utilities";
                case "Education":
                case "Science":      return "applications-science";
            }
        }
        return "";
    }
    function resolveIcon(app) {
        var name = app.icon || "";
        if (name.indexOf("/") !== -1) return "file://" + name;
        var dot = name.lastIndexOf(".");
        if (dot > 0) {
            var ext = name.substring(dot).toLowerCase();
            if (ext === ".svg" || ext === ".png" || ext === ".xpm")
                name = name.substring(0, dot);
        }
        var primary = name ? Quickshell.iconPath(name) : "";
        if (primary) return primary;
        var cat = _categoryIcon(app.categories);
        if (cat) {
            var catPath = Quickshell.iconPath(cat);
            if (catPath) return catPath;
        }
        return Quickshell.iconPath("application-x-executable");
    }

    // Wrapper calls this when the launcher becomes the active center
    // popout. Resets the search input + selection and routes keyboard
    // focus to the input after a 60 ms tick so the Wayland surface has
    // been mapped (Qt.callLater fires too early; forceActiveFocus is a
    // no-op before mapping).
    function focusSearch() {
        searchInput.text = "";
        list.selectedIndex = 0;
        focusTimer.restart();
    }
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: 12
            color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
            border.color: searchInput.activeFocus
                ? root.cPrimary
                : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Text {
                    text: ""
                    color: root.cMuted
                    font.family: root.fontFamily
                    font.pixelSize: 16
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.cFg
                    font.family: root.fontFamily
                    font.pixelSize: 16
                    selectByMouse: true
                    focus: true

                    Keys.onEscapePressed: root.requestClose()
                    Keys.onReturnPressed: list.launchSelected()
                    Keys.onEnterPressed:  list.launchSelected()
                    Keys.onDownPressed:   list.selectNext()
                    Keys.onUpPressed:     list.selectPrev()
                    Keys.onPressed: (e) => {
                        if (e.modifiers & Qt.ControlModifier) {
                            if (e.key === Qt.Key_J) { list.selectNext(); e.accepted = true; }
                            else if (e.key === Qt.Key_K) { list.selectPrev(); e.accepted = true; }
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        text: "Search applications..."
                        color: root.cMuted
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        visible: searchInput.text.length === 0
                    }
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            property int selectedIndex: 0

            readonly property var filtered: {
                var fr = root.frecencyData;
                var query = searchInput.text.toLowerCase().trim();
                var apps = DesktopEntries.applications.values
                    .filter(a => !a.noDisplay);
                if (!query) {
                    return apps.slice().sort((a, b) => {
                        var fa = root._frecencyScore(a);
                        var fb = root._frecencyScore(b);
                        if (fa !== fb) return fb - fa;
                        return (a.name || "").localeCompare(b.name || "");
                    });
                }
                var scored = [];
                for (var i = 0; i < apps.length; i++) {
                    var s = root._appScore(apps[i], query);
                    if (s < 0) continue;
                    var boost = Math.log(1 + root._frecencyScore(apps[i])) * 25;
                    scored.push({ app: apps[i], score: s + boost });
                }
                scored.sort((a, b) => b.score - a.score
                    || (a.app.name || "").localeCompare(b.app.name || ""));
                return scored.map(x => x.app);
            }

            model: filtered
            onFilteredChanged: selectedIndex = 0

            function selectNext() {
                if (count > 0) selectedIndex = Math.min(selectedIndex + 1, count - 1);
                positionViewAtIndex(selectedIndex, ListView.Contain);
            }
            function selectPrev() {
                if (count > 0) selectedIndex = Math.max(selectedIndex - 1, 0);
                positionViewAtIndex(selectedIndex, ListView.Contain);
            }
            function launchSelected() {
                if (count === 0) return;
                var app = filtered[selectedIndex];
                if (app) {
                    root._bump(app);
                    app.execute();
                    root.requestClose();
                }
            }
            function launch(app) {
                root._bump(app);
                app.execute();
                root.requestClose();
            }

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                implicitHeight: 52
                radius: 10
                color: list.selectedIndex === index
                    ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)
                    : (itemMa.containsMouse
                        ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                        : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    IconImage {
                        implicitSize: 32
                        source: root.resolveIcon(modelData)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name || ""
                        color: root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: itemMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: list.selectedIndex = index
                    onClicked: list.launch(modelData)
                }
            }
        }
    }
}
