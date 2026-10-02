import qs.CustomTheme
import QtQuick
import QtQuick.Layouts

// A small month: the sidebar calendar and the cells of the year view.
ColumnLayout {
    id: mm
    property int year: new Date().getFullYear()
    property int month: new Date().getMonth()     // 0-11
    property var selected: null                    // Date or null
    property bool showTitle: true
    property var busy: ({})                        // "yyyy-MM-dd": true for a dot
    signal clickedDay(var date)
    signal clickedTitle()

    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7   // 0 = Sunday
    readonly property var cells: {
        const first = new Date(mm.year, mm.month, 1)
        const offset = (first.getDay() - mm.firstDay + 7) % 7
        return Array.from({ length: 42 }, (_, i) => new Date(mm.year, mm.month, 1 - offset + i))
    }
    function same(a: var, b: var): bool {
        return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    spacing: 4

    Text {
        visible: mm.showTitle
        textFormat: Text.PlainText
        text: Qt.locale().standaloneMonthName(mm.month, Locale.LongFormat)
        color: Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.px(Theme.fontBody)
        font.weight: Font.DemiBold
        MouseArea { anchors.fill: parent; onClicked: mm.clickedTitle() }
    }
    GridLayout {
        columns: 7
        rowSpacing: 1
        columnSpacing: 1
        Repeater {
            model: 7
            Text {
                required property int index
                textFormat: Text.PlainText
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().standaloneDayName((mm.firstDay + index) % 7, Locale.NarrowFormat)
                color: Theme.fgA(0.45)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.px(10)
            }
        }
        Repeater {
            model: mm.cells
            Rectangle {
                required property var modelData
                readonly property bool inMonth: modelData.getMonth() === mm.month
                readonly property bool today: mm.same(modelData, new Date())
                readonly property bool sel: mm.same(modelData, mm.selected)
                Layout.preferredWidth: 24
                Layout.preferredHeight: 22
                radius: 11
                color: today ? Theme.red : sel ? Theme.fgA(0.18) : "transparent"
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: `${modelData.getDate()}`
                    color: parent.today ? "white" : parent.inMonth ? Theme.fg : Theme.fgA(0.3)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.px(11)
                    font.weight: parent.today ? Font.Bold : Font.Normal
                }
                Rectangle {
                    visible: parent.inMonth && !!mm.busy[Qt.formatDate(modelData, "yyyy-MM-dd")]
                    width: 3; height: 3; radius: 2
                    color: Theme.fgA(0.5)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                }
                MouseArea { anchors.fill: parent; onClicked: mm.clickedDay(modelData) }
            }
        }
    }
}
