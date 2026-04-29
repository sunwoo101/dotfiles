// TrayMenuContent — cascading inline rendering of a SystemTrayItem's menu.
// Hosted inside the shared Popouts wrapper.
//
// Cascade layout: the root menu is the rightmost column (closest to the
// tray icon's anchor); each opened submenu adds another column to its
// left. Hovering a parent entry for ~300 ms pushes its handle onto
// `menuPath` at the appropriate depth, replacing any deeper open levels.
// The cursor can travel between columns without closing anything because
// they're all part of the same popout's hit area.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property var trayItem: null
    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    signal requestClose()

    readonly property int columnWidth:    220
    readonly property int padding:        8
    readonly property int rowHeight:     30
    readonly property int columnSpacing:  6
    readonly property int submenuOpenDelay: 300

    // Path of menu handles being rendered as columns. menuPath[0] is the
    // root (rendered rightmost); menuPath[N] is a submenu opened from a
    // parent at level N-1 (rendered to the left).
    property var menuPath: []

    function setLevel(level, handle) {
        // Replace anything deeper than `level` with the new handle.
        menuPath = [...menuPath.slice(0, level + 1), handle];
    }
    function resetMenu(rootHandle) {
        menuPath = rootHandle ? [rootHandle] : [];
    }

    onTrayItemChanged: resetMenu(trayItem ? trayItem.menu : null)
    Component.onCompleted: resetMenu(trayItem ? trayItem.menu : null)

    // Strip GTK-style mnemonic underscores: "_Enable Wi-Fi" → "Enable Wi-Fi",
    // "Save __as__" → "Save _as_". Leaves CJK-style "(_E)" suffixes alone
    // intentionally — they're not common enough to be worth special-casing.
    function _stripMnemonic(s) {
        if (!s) return "";
        var out = "";
        for (var i = 0; i < s.length; i++) {
            var c = s[i];
            if (c === "_" && i + 1 < s.length && s[i + 1] === "_") {
                out += "_";
                i++;
            } else if (c !== "_") {
                out += c;
            }
        }
        return out;
    }

    implicitWidth:  cascade.implicitWidth
    implicitHeight: cascade.implicitHeight

    // Cascade row — RightToLeft so menuPath[0] sits on the right.
    Row {
        id: cascade
        layoutDirection: Qt.RightToLeft
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.columnSpacing

        Repeater {
            model: root.menuPath

            // One column per menu level.
            Item {
                id: levelCol
                required property var modelData     // QsMenuHandle for this level
                required property int index          // level index in menuPath

                implicitWidth:  root.columnWidth
                implicitHeight: levelInner.implicitHeight + root.padding * 2

                QsMenuOpener {
                    id: levelOpener
                    menu: levelCol.modelData
                }

                Column {
                    id: levelInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.padding
                    spacing: 2

                    // Tooltip / title header — root column only.
                    Item {
                        readonly property string headerText: root.trayItem
                            ? (root.trayItem.tooltipTitle || root.trayItem.title || "")
                            : ""
                        readonly property string descText: root.trayItem
                            ? (root.trayItem.tooltipDescription || "")
                            : ""
                        visible: levelCol.index === 0 && headerText !== ""
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: visible
                            ? headerCol.implicitHeight + 6
                            : 0

                        Column {
                            id: headerCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.bottomMargin: 4
                            spacing: 1

                            Text {
                                width: parent.width
                                text: parent.parent.headerText
                                color: root.cPrimary
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: parent.parent.descText
                                color: root.cMuted
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                    }

                    Repeater {
                        model: levelOpener.children

                        Item {
                            id: entryItem
                            required property QsMenuEntry modelData

                            readonly property bool isSeparator: modelData.isSeparator
                            readonly property bool isEnabled:   modelData.enabled
                            readonly property bool hasChildren: modelData.hasChildren
                            readonly property bool isExpanded:
                                hasChildren
                                && root.menuPath.length > levelCol.index + 1
                                && root.menuPath[levelCol.index + 1] === modelData

                            anchors.left: parent ? parent.left  : undefined
                            anchors.right: parent ? parent.right : undefined
                            implicitHeight: isSeparator ? 9 : root.rowHeight

                            Rectangle {
                                visible: entryItem.isSeparator
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                height: 1
                                color: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.10)
                            }

                            Rectangle {
                                visible: !entryItem.isSeparator
                                anchors.fill: parent
                                radius: 8
                                color: (entryMa.containsMouse && entryItem.isEnabled) || entryItem.isExpanded
                                    ? Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.12)
                                    : "transparent"
                                opacity: entryItem.isEnabled ? 1.0 : 0.45
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Check / radio indicator for checkable
                                    // entries. nm-applet uses these for
                                    // Wi-Fi / networking toggles, so
                                    // without this users can't tell whether
                                    // "Enable Wi-Fi" is on.
                                    TintedIcon {
                                        readonly property int btn: entryItem.modelData.buttonType
                                        readonly property int state: entryItem.modelData.checkState
                                        // QsMenuButtonType: None=0, CheckBox=1, RadioButton=2
                                        // Qt.CheckState: Unchecked=0, PartiallyChecked=1, Checked=2
                                        visible: btn !== 0
                                        name: btn === 2
                                            ? (state === 2 ? "radio-checked-symbolic" : "radio-symbolic")
                                            : (state === 2 ? "checkbox-checked-symbolic" : "checkbox-symbolic")
                                        tint: state === 2 ? root.cPrimary : root.cMuted
                                        size: 14
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                    }

                                    Image {
                                        visible: source.toString() !== ""
                                            && entryItem.modelData.buttonType === 0
                                        source: entryItem.modelData.icon
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        sourceSize.width:  32
                                        sourceSize.height: 32
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root._stripMnemonic(entryItem.modelData.text)
                                        color: root.cFg
                                        font.family: root.fontFamily
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }

                                    TintedIcon {
                                        visible: entryItem.hasChildren
                                        name: "pan-end-symbolic"
                                        tint: entryItem.isExpanded ? root.cPrimary : root.cMuted
                                        size: 14
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                    }
                                }

                                MouseArea {
                                    id: entryMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: entryItem.isEnabled && !entryItem.isSeparator

                                    onClicked: {
                                        if (entryItem.hasChildren) {
                                            root.setLevel(levelCol.index, entryItem.modelData);
                                        } else {
                                            entryItem.modelData.triggered();
                                            root.requestClose();
                                        }
                                    }

                                    // Hover dwell to expand a parent entry,
                                    // and on hovering a leaf entry trim any
                                    // deeper open submenu.
                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            if (entryItem.hasChildren) {
                                                hoverTimer.restart();
                                            } else {
                                                hoverTimer.stop();
                                                // If the cursor lands on a
                                                // leaf entry, close any
                                                // submenu that was opened
                                                // by a sibling parent.
                                                root.menuPath = root.menuPath.slice(0, levelCol.index + 1);
                                            }
                                        } else {
                                            hoverTimer.stop();
                                        }
                                    }
                                    Timer {
                                        id: hoverTimer
                                        interval: root.submenuOpenDelay
                                        onTriggered: {
                                            if (entryMa.containsMouse && entryItem.hasChildren) {
                                                root.setLevel(levelCol.index, entryItem.modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Fallback when the root menu is empty.
                    Item {
                        visible: levelOpener.children.values.length === 0
                            && levelCol.index === 0
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: visible ? root.rowHeight : 0

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: root.trayItem
                                ? (root.trayItem.tooltipTitle || root.trayItem.title || "(no menu)")
                                : "(no item)"
                            color: root.cMuted
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
