// NotificationsContent — content-only (no PanelWindow). Hosted inside the
// shared Popouts wrapper.
//
// Notifications are grouped by appName. Single-notif groups render as a
// regular card (clicking invokes default action). Multi-notif groups
// render compactly with the latest visible; clicking the card or the
// chevron expands to show all notifs in that group, each clickable
// individually. Each notif shows its arrival age relative to shellRoot._notifNow.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property var notifServer
    required property var popped
    required property var notifReceivedAt
    required property real now
    required property var expireCallback
    required property var clearAllCallback
    required property bool hovered
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    readonly property int contentWidth:     480
    readonly property int padding:          16
    readonly property int maxContentHeight: 600

    // Per-app expand state. Keyed by appName.
    property var expandedGroups: ({})
    function toggleGroup(appName) {
        var c = Object.assign({}, expandedGroups);
        c[appName] = !c[appName];
        expandedGroups = c;
    }

    // Group source notifications by appName, preserving newest-first order.
    readonly property var groupedDisplay: {
        var src = hovered ? notifServer.trackedNotifications.values : popped;
        var groups = {};
        var order = [];
        for (var i = src.length - 1; i >= 0; i--) {
            var n = src[i];
            var key = n.appName || "Unknown";
            if (!groups[key]) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(n);
        }
        return order.map(k => ({ appName: k, notifs: groups[k] }));
    }

    function formatAge(ts) {
        if (!ts) return "";
        var diff = Math.max(0, root.now - ts);
        var s = Math.floor(diff / 1000);
        if (s < 30)  return "now";
        if (s < 60)  return s + "s";
        var m = Math.floor(s / 60);
        if (m < 60)  return m + "m";
        var h = Math.floor(m / 60);
        if (h < 24)  return h + "h";
        var d = Math.floor(h / 24);
        return d + "d";
    }

    function _openOrDismiss(n) {
        var hints = n.hints || {};
        if (hints["x-screenshot-dir"]) {
            openProc.command = ["xdg-open", hints["x-screenshot-dir"]];
            openProc.running = true;
            root.expireCallback(n);
            n.dismiss();
            return;
        }
        var actions = n.actions || [];
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].identifier === "default") {
                actions[i].invoke();
                return;
            }
        }
        root.expireCallback(n);
        n.dismiss();
    }

    function _altActions(n) {
        var out = [];
        var actions = (n && n.actions) || [];
        for (var i = 0; i < actions.length; i++) {
            if (actions[i].identifier !== "default") out.push(actions[i]);
        }
        return out;
    }

    function _dismissAll(notifs) {
        var ns = notifs.slice();
        for (var i = 0; i < ns.length; i++) {
            root.expireCallback(ns[i]);
            ns[i].dismiss();
        }
    }

    implicitWidth:  contentWidth
    implicitHeight: Math.min(column.implicitHeight + padding * 2, maxContentHeight)

    Process { id: openProc; running: false }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.padding
        contentHeight: column.implicitHeight
        contentWidth:  width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: parent.width
            spacing: 8

            CardButton {
                width: parent.width
                implicitHeight: 32
                visible: root.hovered && root.notifServer.trackedNotifications.values.length > 0
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root.clearAllCallback()
                Text {
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: root.cFg
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }
            }

            Text {
                visible: root.groupedDisplay.length === 0 && root.hovered
                text: "No notifications"
                color: root.cMuted
                font.family: root.fontFamily
                font.pixelSize: 15
                topPadding: 4
            }

            Repeater {
                model: root.groupedDisplay

                Rectangle {
                    id: groupCard
                    required property var modelData    // { appName, notifs[] }

                    readonly property var notifs:    modelData.notifs
                    readonly property string appName: modelData.appName
                    readonly property int count:     notifs.length
                    readonly property var latest:    notifs[0]
                    readonly property bool isGroup:  count > 1
                    readonly property bool expanded: root.expandedGroups[appName] === true
                    readonly property var visibleNotifs: (!isGroup || expanded) ? notifs : [latest]

                    width: column.width
                    implicitHeight: groupCol.implicitHeight + 24
                    radius: 12
                    color: groupHover.hovered
                        ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                        : Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.06)
                    border.color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: groupHover }

                    // Outer dead-zone click handler. Inner MouseAreas
                    // (per-notif click area, close buttons, alt actions)
                    // sit deeper in the tree and intercept their own
                    // clicks first; anything that falls through (header
                    // padding, group margins, separators) lands here.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!groupCard.isGroup) {
                                root._openOrDismiss(groupCard.latest);
                            } else {
                                root.toggleGroup(groupCard.appName);
                            }
                        }
                    }

                    ColumnLayout {
                        id: groupCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // ---- Header ------------------------------------
                        Item {
                            id: headerWrap
                            Layout.fillWidth: true
                            implicitHeight: headerRow.implicitHeight

                            RowLayout {
                                id: headerRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: groupCard.appName
                                        + (groupCard.isGroup ? "  (" + groupCard.count + ")" : "")
                                    color: root.cPrimary
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.formatAge(root.notifReceivedAt[groupCard.latest.id])
                                    color: root.cMuted
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    visible: text !== ""
                                }

                                TintedIcon {
                                    name: groupCard.expanded ? "pan-down-symbolic" : "pan-end-symbolic"
                                    tint: root.cMuted
                                    size: 16
                                    visible: groupCard.isGroup
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                }

                                CardButton {
                                    id: groupCloseBtn
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    cFg: root.cFg
                                    cPrimary: root.cPrimary
                                    onClicked: root._dismissAll(groupCard.notifs)

                                    Shape {
                                        anchors.centerIn: parent
                                        width: 12; height: 12
                                        ShapePath {
                                            strokeColor: groupCloseBtn.hovered ? root.cFg : root.cMuted
                                            strokeWidth: 1.8
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            startX: 0; startY: 0
                                            PathLine { x: 12; y: 12 }
                                        }
                                        ShapePath {
                                            strokeColor: groupCloseBtn.hovered ? root.cFg : root.cMuted
                                            strokeWidth: 1.8
                                            capStyle: ShapePath.RoundCap
                                            fillColor: "transparent"
                                            startX: 12; startY: 0
                                            PathLine { x: 0; y: 12 }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Notif list --------------------------------
                        Repeater {
                            model: groupCard.visibleNotifs

                            Item {
                                id: notifItem
                                required property var modelData
                                required property int index
                                readonly property var n: modelData
                                readonly property var notifAlts: root._altActions(n)
                                readonly property bool showItemMeta:
                                    groupCard.isGroup && groupCard.expanded

                                Layout.fillWidth: true
                                implicitHeight: notifCol.implicitHeight
                                    + (showItemMeta && index > 0 ? 9 : 0)

                                // Separator above expanded items (except the first).
                                Rectangle {
                                    visible: notifItem.showItemMeta && notifItem.index > 0
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                                }

                                // Click area covering the whole notif item
                                // (including the separator strip above it
                                // when expanded). For single-notif groups
                                // and expanded multi-notif this opens that
                                // notif's default action. In collapsed
                                // multi-notif we let the click fall through
                                // to the outer card MouseArea (toggle
                                // expand) — `enabled: false` here means the
                                // event isn't intercepted.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !groupCard.isGroup || groupCard.expanded
                                    onClicked: root._openOrDismiss(notifItem.n)
                                }

                                ColumnLayout {
                                    id: notifCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: notifItem.showItemMeta && notifItem.index > 0 ? 9 : 0
                                    spacing: 4

                                    // Per-item meta row (summary + age + close)
                                    // — only shown for items inside an expanded
                                    // multi-notif group, since the group header
                                    // already shows app+age for collapsed/single.
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        visible: notifItem.showItemMeta

                                        Text {
                                            Layout.fillWidth: true
                                            text: notifItem.n.summary || ""
                                            color: root.cFg
                                            font.family: root.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: root.formatAge(root.notifReceivedAt[notifItem.n.id])
                                            color: root.cMuted
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                            visible: text !== ""
                                        }
                                        CardButton {
                                            id: itemCloseBtn
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            radius: 11
                                            cFg: root.cFg
                                            cPrimary: root.cPrimary
                                            onClicked: {
                                                root.expireCallback(notifItem.n);
                                                notifItem.n.dismiss();
                                            }

                                            Shape {
                                                anchors.centerIn: parent
                                                width: 10; height: 10
                                                ShapePath {
                                                    strokeColor: itemCloseBtn.hovered ? root.cFg : root.cMuted
                                                    strokeWidth: 1.6
                                                    capStyle: ShapePath.RoundCap
                                                    fillColor: "transparent"
                                                    startX: 0; startY: 0
                                                    PathLine { x: 10; y: 10 }
                                                }
                                                ShapePath {
                                                    strokeColor: itemCloseBtn.hovered ? root.cFg : root.cMuted
                                                    strokeWidth: 1.6
                                                    capStyle: ShapePath.RoundCap
                                                    fillColor: "transparent"
                                                    startX: 10; startY: 0
                                                    PathLine { x: 0; y: 10 }
                                                }
                                            }
                                        }
                                    }

                                    // Summary in collapsed/single mode (the
                                    // larger headline-style summary).
                                    Text {
                                        Layout.fillWidth: true
                                        text: notifItem.n.summary || ""
                                        color: root.cFg
                                        font.family: root.fontFamily
                                        font.pixelSize: 16
                                        font.bold: true
                                        elide: Text.ElideRight
                                        visible: !notifItem.showItemMeta && text !== ""
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: notifItem.n.body || ""
                                        color: root.cPrimary
                                        font.family: root.fontFamily
                                        font.pixelSize: 14
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        visible: text !== ""
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6
                                        visible: notifItem.notifAlts.length > 0

                                        Repeater {
                                            model: notifItem.notifAlts

                                            CardButton {
                                                id: altBtn
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 30
                                                cFg: root.cFg
                                                cPrimary: root.cPrimary
                                                onClicked: altBtn.modelData.invoke()
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: altBtn.modelData.text || altBtn.modelData.identifier
                                                    color: root.cFg
                                                    font.family: root.fontFamily
                                                    font.pixelSize: 13
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
