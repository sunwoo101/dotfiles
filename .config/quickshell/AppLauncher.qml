// AppLauncher — centered drop-down launcher hanging from the bar. Top+center
// aligned: inverse top-LEFT and top-RIGHT merge into the bar; rounded
// bottom-LEFT and bottom-RIGHT. Open state and IPC live in shell.qml.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Modal {
    id: root

    edge:  "top"
    align: "center"
    contentWidth:  640
    contentHeight: 520
    cornerRadius:  16
    closeOnOutsideClick: true

    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    readonly property int padding: 16

    // Icon resolution with category-aware fallback.
    //   1. exact `Icon=` from the .desktop entry
    //   2. generic icon mapped from the entry's `Categories=` field
    //   3. application-x-executable (generic gear)
    // Quickshell.iconPath(name) returns "" when the icon isn't in the theme,
    // which lets us cascade.
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
        // Absolute / relative path in the Icon= field — use it literally.
        // .desktop files for some apps (e.g. Steam shortcuts) put a full
        // PNG path here instead of a theme name.
        if (name.indexOf("/") !== -1) return "file://" + name;
        // Some apps put an extension on the icon name (e.g.
        // "netflix-desktop.svg"). The spec forbids it, but the theme stores
        // the file as "netflix-desktop", so strip it before the lookup.
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

    // Exclusive grabs focus immediately on show; OnDemand requires a click
    // first, leaving the search input dead until interaction.
    WlrLayershell.keyboardFocus: open ? WlrLayershell.Exclusive : WlrLayershell.None

    onOpenChanged: {
        if (open) {
            searchInput.text = "";
            list.selectedIndex = 0;
            // delay the focus grab until after the Wayland surface is mapped
            // and the compositor has routed keyboard focus to the layer —
            // Qt.callLater fires too early and forceActiveFocus is a no-op.
            focusTimer.restart();
        }
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
                var query = searchInput.text.toLowerCase().trim();
                return DesktopEntries.applications.values
                    .filter(a => !a.noDisplay)
                    .filter(a => {
                        if (!query) return true;
                        var rawExec = (a.command && a.command[0])
                            || (a.exec || "").split(" ")[0]
                            || "";
                        var bin = rawExec.split("/").pop().toLowerCase();
                        var hay = [
                            a.name, a.genericName, a.comment, a.id,
                            bin, (a.keywords || []).join(" ")
                        ].join(" ").toLowerCase();
                        return hay.includes(query);
                    })
                    .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
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
                    app.execute();
                    root.requestClose();
                }
            }
            function launch(app) {
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
