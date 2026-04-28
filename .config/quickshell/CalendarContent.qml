// CalendarContent — content-only month-grid calendar. Hosted by the
// shared Popouts wrapper.

import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property color cBg
    required property color cFg
    required property color cPrimary
    required property color cMuted
    required property string fontFamily

    readonly property int contentWidth:  280
    readonly property int contentHeight: 280
    readonly property int padding: 14

    implicitWidth:  contentWidth
    implicitHeight: contentHeight

    property date today: new Date()
    property int viewedYear:  today.getFullYear()
    property int viewedMonth: today.getMonth()    // 0..11

    Timer {
        interval: 60000
        running: true; repeat: true
        onTriggered: root.today = new Date()
    }

    function _monthName(m) {
        return ["January","February","March","April","May","June",
                "July","August","September","October","November","December"][m];
    }
    function _daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
    function _firstWeekday(y, m) {
        var d = new Date(y, m, 1).getDay();   // 0=Sun..6=Sat
        return (d + 6) % 7;                   // Mon-first: 0=Mon..6=Sun
    }
    function _shiftMonth(delta) {
        var m = viewedMonth + delta;
        var y = viewedYear;
        while (m < 0)  { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        viewedMonth = m;
        viewedYear  = y;
    }

    readonly property int _firstDow:  _firstWeekday(viewedYear, viewedMonth)
    readonly property int _daysCount: _daysInMonth(viewedYear, viewedMonth)
    readonly property var _cells: {
        var out = [];
        for (var i = 0; i < _firstDow; i++) out.push(0);
        for (var d = 1; d <= _daysCount; d++) out.push(d);
        while (out.length < 42) out.push(0);
        return out;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            CardButton {
                implicitWidth: 28
                implicitHeight: 28
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root._shiftMonth(-1)
                TintedIcon {
                    anchors.centerIn: parent
                    name: "go-previous-symbolic"
                    tint: root.cFg
                    size: 14
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root._monthName(root.viewedMonth) + " " + root.viewedYear
                color: root.cFg
                font.family: root.fontFamily
                font.pixelSize: 14
                font.bold: true
            }
            CardButton {
                implicitWidth: 28
                implicitHeight: 28
                cFg: root.cFg
                cPrimary: root.cPrimary
                onClicked: root._shiftMonth(1)
                TintedIcon {
                    anchors.centerIn: parent
                    name: "go-next-symbolic"
                    tint: root.cFg
                    size: 14
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            columnSpacing: 0
            rowSpacing: 0
            Repeater {
                model: ["M","T","W","T","F","S","S"]
                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: root.cMuted
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            Repeater {
                model: root._cells
                Item {
                    id: cell
                    required property int modelData
                    readonly property bool isToday:
                        modelData > 0
                        && root.viewedYear  === root.today.getFullYear()
                        && root.viewedMonth === root.today.getMonth()
                        && modelData         === root.today.getDate()

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: width / 2
                        color: cell.isToday ? root.cPrimary : "transparent"
                        visible: cell.modelData > 0
                    }
                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData > 0 ? cell.modelData : ""
                        color: cell.isToday ? root.cBg : root.cFg
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
