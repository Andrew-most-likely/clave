import Quickshell
import Quickshell.Io
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

// Calendar (PROJECT_PLAN.md APP-8). Day, week, month and year views, a sidebar
// with the calendars and a small month, and event details in a pop-over.
// One .ics file per calendar in ~/.local/share/clave/calendars, read and
// written by clave-pim (python-icalendar, python-dateutil); this file only
// draws. No sync, no accounts, no network. A notice appears when an event
// starts only while Calendar is open: there is no alarm service (PERF-1).
FloatingWindow {
    id: root
    title: "Calendar"
    color: Theme.window
    implicitWidth: 1120
    implicitHeight: 740
    onVisibleChanged: if (!visible) Qt.quit()

    readonly property string pim: Quickshell.env("HOME") + "/.local/bin/clave-pim"
    property string view: "month"                 // day, week, month, year
    property var cursor: root.dayStart(new Date())
    property var calendars: []
    property var hidden: ({})
    property var events: []
    property var editing: null                    // event being edited, or null
    property string error: ""

    // ---------------------------------------------------------------- dates
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    function dayStart(d: var): var { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function addDays(d: var, n: int): var { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    function iso(d: var): string { return Qt.formatDateTime(d, "yyyy-MM-ddTHH:mm:ss") }
    function isoDate(d: var): string { return Qt.formatDate(d, "yyyy-MM-dd") }
    function parse(s: string): var {
        const m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?/)
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0)) : null
    }
    function same(a: var, b: var): bool { return root.isoDate(a) === root.isoDate(b) }
    function weekStart(d: var): var { return root.addDays(d, -((d.getDay() - root.firstDay + 7) % 7)) }
    readonly property var range: {
        const c = root.cursor
        if (root.view === "day") return [c, root.addDays(c, 1)]
        if (root.view === "week") { const s = root.weekStart(c); return [s, root.addDays(s, 7)] }
        if (root.view === "year") return [new Date(c.getFullYear(), 0, 1), new Date(c.getFullYear() + 1, 0, 1)]
        const s = root.weekStart(new Date(c.getFullYear(), c.getMonth(), 1))
        return [s, root.addDays(s, 42)]
    }
    readonly property string heading: {
        const c = root.cursor
        if (root.view === "day") return Qt.formatDate(c, "d MMMM yyyy")
        if (root.view === "year") return `${c.getFullYear()}`
        if (root.view === "week") {
            const s = root.range[0], e = root.addDays(root.range[1], -1)
            return s.getMonth() === e.getMonth() ? Qt.formatDate(s, "MMMM yyyy")
                : Qt.formatDate(s, "MMM") + " – " + Qt.formatDate(e, "MMM yyyy")
        }
        return Qt.formatDate(c, "MMMM yyyy")
    }
    function step(n: int): void {
        const c = root.cursor
        if (root.view === "day") root.cursor = root.addDays(c, n)
        else if (root.view === "week") root.cursor = root.addDays(c, 7 * n)
        else if (root.view === "month") root.cursor = new Date(c.getFullYear(), c.getMonth() + n, 1)
        else root.cursor = new Date(c.getFullYear() + n, c.getMonth(), 1)
    }

    readonly property var shown: root.events.filter(e => !root.hidden[e.calendar])
    function eventsOn(d: var): var {
        const s = root.dayStart(d), e = root.addDays(s, 1)
        return root.shown.filter(ev => root.parse(ev.start) < e && root.parse(ev.end) > s
                                      && !(ev.allDay && root.parse(ev.end) <= s))
    }
    readonly property var busyDays: {
        let b = {}
        root.shown.forEach(ev => {
            for (let d = root.dayStart(root.parse(ev.start)); d < root.parse(ev.end); d = root.addDays(d, 1))
                b[root.isoDate(d)] = true
        })
        return b
    }

    // ---------------------------------------------------------------- data
    Process {
        id: calProc
        command: [root.pim, "calendars"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { root.calendars = JSON.parse(this.text) } catch (e) {} ; root.reload() }
        }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }
    Process {
        id: evProc
        stdout: StdioCollector { onStreamFinished: { try { root.events = JSON.parse(this.text) } catch (e) {} } }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }
    function reload(): void {
        evProc.running = false
        evProc.command = [root.pim, "events", root.iso(root.range[0]), root.iso(root.range[1])]
        evProc.running = true
    }
    onRangeChanged: root.reload()

    // Writes: stdin carries the event as JSON; nothing goes through a shell.
    Process {
        id: saver
        property string payload: ""
        stdinEnabled: true
        onRunningChanged: if (running && payload !== "") { write(payload); stdinEnabled = false }
        onExited: code => { saver.payload = ""; saver.stdinEnabled = true; root.reload() }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }
    Process {
        id: action
        onExited: { calProc.running = false; calProc.running = true }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }
    function run(args: var): void { action.running = false; action.command = [root.pim, ...args]; action.running = true }

    function newEvent(start: var, allDay: bool): void {
        const s = allDay ? root.dayStart(start) : start
        root.editing = { "uid": "", "calendar": (root.calendars.find(c => !root.hidden[c.id]) || root.calendars[0] || { "id": "Calendar" }).id,
                         "title": "", "location": "", "notes": "", "allDay": allDay, "repeat": "", "repeats": false,
                         "start": root.iso(s), "end": root.iso(allDay ? root.addDays(s, 1) : new Date(s.getTime() + 3600000)) }
    }
    function save(ev: var): void {
        if (saver.running) return
        saver.payload = JSON.stringify(ev)
        saver.stdinEnabled = true
        saver.command = [root.pim, "event-save"]
        saver.running = true
        root.editing = null
    }
    function remove(ev: var, onlyThis: bool): void {
        root.run(onlyThis ? ["event-delete", ev.calendar, ev.uid, ev.occurrence] : ["event-delete", ev.calendar, ev.uid])
        root.editing = null
    }

    // Reminders while open: a notice when an event starts.
    property var notified: ({})
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            const now = new Date()
            root.shown.forEach(ev => {
                if (ev.allDay) return
                const s = root.parse(ev.start)
                const key = ev.uid + ev.start
                if (s <= now && now - s < 60000 && !root.notified[key]) {
                    root.notified[key] = true
                    Quickshell.execDetached(["notify-send", "-a", "Calendar", "-i", "x-office-calendar",
                        ev.title || "Event", Qt.formatTime(s, "HH:mm") + (ev.location ? " · " + ev.location : "")])
                }
            })
        }
    }

    FileDialog {
        id: importDialog
        title: "Import a calendar"
        nameFilters: ["Calendars (*.ics)"]
        onAccepted: root.run(["import", decodeURIComponent(`${selectedFile}`.replace(/^file:\/\//, ""))])
    }

    Shortcut { sequence: "Ctrl+N"; onActivated: root.newEvent(new Date(root.cursor.getFullYear(), root.cursor.getMonth(), root.cursor.getDate(), 9), false) }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.cursor = root.dayStart(new Date()) }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.view = "day" }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.view = "week" }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.view = "month" }
    Shortcut { sequence: "Ctrl+4"; onActivated: root.view = "year" }
    Shortcut { sequence: "Escape"; onActivated: root.editing = null }

    // ---------------------------------------------------------------- layout
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar: calendars and a small month
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.sidebar
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 40
                spacing: 4
                Text {
                    textFormat: Text.PlainText
                    text: "Calendars"
                    color: Theme.fgA(0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: root.calendars
                    RowLayout {
                        required property var modelData
                        spacing: 8
                        Rectangle {
                            implicitWidth: 14; implicitHeight: 14; radius: 3
                            color: root.hidden[modelData.id] ? "transparent" : modelData.color
                            border.width: 2
                            border.color: modelData.color
                            Text { anchors.centerIn: parent; visible: !root.hidden[modelData.id]; text: "✓"; color: "white"; font.pixelSize: 10 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { let h = Object.assign({}, root.hidden); h[modelData.id] = !h[modelData.id]; root.hidden = h }
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: modelData.name + (modelData.error ? " (cannot read)" : "")
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                        }
                    }
                }
                RowLayout {
                    spacing: 4
                    AppButton {
                        label: "+ New"
                        tip: "New Calendar"
                        onClicked: {
                            let n = root.calendars.length + 1
                            while (root.calendars.some(c => c.id === "Calendar " + n)) n++
                            root.run(["calendar-new", "Calendar " + n])
                        }
                    }
                    AppButton { label: "Import…"; tip: "Copy an .ics file into Calendar"; onClicked: importDialog.open() }
                }
                Item { Layout.fillHeight: true }
                MiniMonth {
                    year: root.cursor.getFullYear()
                    month: root.cursor.getMonth()
                    selected: root.cursor
                    busy: root.busyDays
                    onClickedDay: d => root.cursor = d
                }
            }
        }
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.fgA(0.1) }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Toolbar
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.topMargin: 34
                spacing: 6
                AppButton {
                    label: "+"
                    tip: "New Event (Ctrl+N)"
                    onClicked: root.newEvent(new Date(root.cursor.getFullYear(), root.cursor.getMonth(), root.cursor.getDate(), 9), false)
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: seg.implicitWidth + 4
                    implicitHeight: 26
                    radius: Theme.radiusControl
                    color: Theme.fgA(0.08)
                    Row {
                        id: seg
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [["day", "Day"], ["week", "Week"], ["month", "Month"], ["year", "Year"]]
                            Rectangle {
                                required property var modelData
                                width: 64; height: 22
                                radius: Theme.radiusControl - 1
                                color: root.view === modelData[0] ? Theme.control : "transparent"
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: modelData[1]
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBody
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.view = modelData[0] }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                AppButton { label: "‹"; onClicked: root.step(-1) }
                AppButton { label: "Today"; onClicked: root.cursor = root.dayStart(new Date()) }
                AppButton { label: "›"; onClicked: root.step(1) }
            }
            Text {
                textFormat: Text.PlainText
                Layout.leftMargin: 16
                Layout.bottomMargin: 6
                text: root.heading
                color: Theme.fg
                font.family: Theme.displayFamily
                font.pixelSize: 26
                font.weight: Font.Bold
            }
            Text {
                visible: root.error !== ""
                textFormat: Text.PlainText
                Layout.leftMargin: 16
                Layout.fillWidth: true
                text: root.error
                wrapMode: Text.Wrap
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSecondary
                MouseArea { anchors.fill: parent; onClicked: root.error = "" }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.view === "month" ? monthView : root.view === "year" ? yearView : timeView
            }
        }
    }

    // ---------------------------------------------------------------- month
    Component {
        id: monthView
        ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: 7
                    Text {
                        required property int index
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 8
                        text: Qt.locale().standaloneDayName((root.firstDay + index) % 7, Locale.ShortFormat)
                        color: Theme.fgA(0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSecondary
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 0
                columnSpacing: 0
                Repeater {
                    model: 42
                    Rectangle {
                        id: cell
                        required property int index
                        readonly property var day: root.addDays(root.range[0], index)
                        readonly property var evs: root.eventsOn(day)
                        readonly property bool inMonth: day.getMonth() === root.cursor.getMonth()
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1
                        color: root.same(day, root.cursor) ? Theme.fgA(0.05) : "transparent"
                        border.width: 0.5
                        border.color: Theme.fgA(0.1)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.cursor = cell.day
                            onDoubleClicked: root.newEvent(new Date(cell.day.getFullYear(), cell.day.getMonth(), cell.day.getDate(), 9), false)
                        }
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            width: 24; height: 22; radius: 11
                            color: root.same(cell.day, new Date()) ? Theme.red : "transparent"
                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: cell.day.getDate() === 1 ? Qt.formatDate(cell.day, "d MMM") : `${cell.day.getDate()}`
                                color: root.same(cell.day, new Date()) ? "white" : cell.inMonth ? Theme.fg : Theme.fgA(0.3)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                            }
                        }
                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 28; leftMargin: 3; rightMargin: 3 }
                            spacing: 2
                            Repeater {
                                model: cell.evs.slice(0, Math.max(0, Math.floor((cell.height - 30) / 19) - 1) || 1)
                                EventChip { required property var modelData; ev: modelData; width: parent.width }
                            }
                            Text {
                                readonly property int more: cell.evs.length - Math.max(1, Math.floor((cell.height - 30) / 19) - 1)
                                visible: more > 0
                                textFormat: Text.PlainText
                                text: more + " more"
                                leftPadding: 4
                                color: Theme.fgA(0.55)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                            }
                        }
                    }
                }
            }
        }
    }

    component EventChip: Rectangle {
        id: chip
        property var ev
        height: 17
        radius: 4
        color: chip.ev.allDay ? Qt.alpha(chip.ev.color, 0.8) : "transparent"
        Row {
            anchors.fill: parent
            anchors.leftMargin: 4
            spacing: 4
            Rectangle {
                visible: !chip.ev.allDay
                width: 7; height: 7; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: chip.ev.color
            }
            Text {
                textFormat: Text.PlainText
                width: chip.width - 16
                anchors.verticalCenter: parent.verticalCenter
                text: (chip.ev.allDay ? "" : Qt.formatTime(root.parse(chip.ev.start), "HH:mm") + "  ") + (chip.ev.title || "New Event")
                elide: Text.ElideRight
                color: chip.ev.allDay ? "white" : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSecondary
            }
        }
        MouseArea { anchors.fill: parent; onClicked: root.editing = Object.assign({ "oldCalendar": chip.ev.calendar }, chip.ev) }
    }

    // ---------------------------------------------------------------- day and week
    Component {
        id: timeView
        ColumnLayout {
            id: tv
            spacing: 0
            readonly property int days: root.view === "day" ? 1 : 7
            readonly property int hourH: 48
            // All-day row
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 56
                spacing: 0
                Repeater {
                    model: tv.days
                    ColumnLayout {
                        id: head
                        required property int index
                        readonly property var day: root.addDays(root.range[0], index)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 2
                        Text {
                            textFormat: Text.PlainText
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDate(head.day, "ddd d")
                            color: root.same(head.day, new Date()) ? Theme.red : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            font.weight: root.same(head.day, new Date()) ? Font.Bold : Font.Normal
                        }
                        Repeater {
                            model: root.eventsOn(head.day).filter(e => e.allDay)
                            EventChip { required property var modelData; ev: modelData; Layout.fillWidth: true; Layout.margins: 1 }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.fgA(0.12) }
            Flickable {
                id: fl
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: 24 * tv.hourH
                Component.onCompleted: contentY = 8 * tv.hourH
                Item {
                    width: fl.width
                    height: 24 * tv.hourH
                    Repeater {
                        model: 24
                        Item {
                            required property int index
                            y: index * tv.hourH
                            width: parent.width
                            height: tv.hourH
                            Text {
                                textFormat: Text.PlainText
                                x: 6
                                y: -7
                                visible: index > 0
                                text: `${index}`.padStart(2, "0") + ":00"
                                color: Theme.fgA(0.45)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                            Rectangle { x: 56; width: parent.width - 56; height: 1; color: Theme.fgA(0.08) }
                        }
                    }
                    // Now line
                    Rectangle {
                        readonly property var now: new Date()
                        readonly property int col: Math.floor((root.dayStart(now) - root.range[0]) / 86400000)
                        visible: col >= 0 && col < tv.days
                        x: 56 + col * (parent.width - 56) / tv.days
                        width: (parent.width - 56) / tv.days
                        y: (now.getHours() * 60 + now.getMinutes()) / 60 * tv.hourH
                        height: 2
                        color: Theme.red
                    }
                    Repeater {
                        model: tv.days
                        Item {
                            id: col
                            required property int index
                            readonly property var day: root.addDays(root.range[0], index)
                            // Overlapping events share the column side by side.
                            readonly property var laid: {
                                const evs = root.eventsOn(col.day).filter(e => !e.allDay)
                                    .map(e => ({ "ev": e, "s": Math.max(0, (root.parse(e.start) - col.day) / 60000),
                                                 "e": Math.min(1440, (root.parse(e.end) - col.day) / 60000) }))
                                    .sort((a, b) => a.s - b.s)
                                let lanes = []
                                evs.forEach(x => {
                                    let l = lanes.findIndex(end => end <= x.s)
                                    if (l < 0) { l = lanes.length; lanes.push(0) }
                                    lanes[l] = x.e
                                    x.lane = l
                                })
                                evs.forEach(x => x.lanes = Math.max(1, lanes.length))
                                return evs
                            }
                            x: 56 + index * (parent.width - 56) / tv.days
                            width: (parent.width - 56) / tv.days
                            height: parent.height
                            Rectangle { width: 1; height: parent.height; color: Theme.fgA(0.08) }
                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: mouse => {
                                    const mins = Math.floor(mouse.y / tv.hourH * 2) * 30
                                    root.newEvent(new Date(col.day.getFullYear(), col.day.getMonth(), col.day.getDate(), 0, mins), false)
                                }
                            }
                            Repeater {
                                model: col.laid
                                Rectangle {
                                    required property var modelData
                                    x: 2 + modelData.lane * (col.width - 4) / modelData.lanes
                                    width: (col.width - 4) / modelData.lanes - 2
                                    y: modelData.s / 60 * tv.hourH
                                    height: Math.max(18, (modelData.e - modelData.s) / 60 * tv.hourH - 2)
                                    radius: 5
                                    color: Qt.alpha(modelData.ev.color, 0.28)
                                    border.width: 0
                                    Rectangle { width: 3; height: parent.height; radius: 2; color: modelData.ev.color }
                                    Column {
                                        anchors { fill: parent; leftMargin: 7; topMargin: 2; rightMargin: 3 }
                                        Text {
                                            textFormat: Text.PlainText
                                            width: parent.width
                                            text: modelData.ev.title || "New Event"
                                            elide: Text.ElideRight
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSecondary
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            width: parent.width
                                            visible: parent.height > 30
                                            text: Qt.formatTime(root.parse(modelData.ev.start), "HH:mm") + (modelData.ev.location ? " · " + modelData.ev.location : "")
                                            elide: Text.ElideRight
                                            color: Theme.fgA(0.7)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.editing = Object.assign({ "oldCalendar": modelData.ev.calendar }, modelData.ev)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- year
    Component {
        id: yearView
        Flickable {
            clip: true
            contentHeight: yg.implicitHeight + 20
            GridLayout {
                id: yg
                x: 20
                width: parent.width - 40
                columns: 4
                rowSpacing: 18
                columnSpacing: 24
                Repeater {
                    model: 12
                    MiniMonth {
                        required property int index
                        year: root.cursor.getFullYear()
                        month: index
                        selected: root.cursor
                        busy: root.busyDays
                        onClickedDay: d => { root.cursor = d; root.view = "day" }
                        onClickedTitle: { root.cursor = new Date(year, index, 1); root.view = "month" }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- event pop-over
    Rectangle {
        anchors.fill: parent
        visible: root.editing !== null
        color: Qt.rgba(0, 0, 0, 0.25)
        MouseArea { anchors.fill: parent; onClicked: root.editing = null }
    }
    Rectangle {
        id: pop
        visible: root.editing !== null
        anchors.centerIn: parent
        width: 380
        height: form.implicitHeight + 28
        radius: Theme.radiusCard
        color: Theme.popup
        border.color: Theme.fgA(0.15)
        property var ev: root.editing || ({})
        onEvChanged: if (root.editing) {
            title.text = ev.title || ""
            location.text = ev.location || ""
            notes.text = ev.notes || ""
            allDay.checked = !!ev.allDay
            const s = root.parse(ev.start || root.iso(new Date())), e = root.parse(ev.end || root.iso(new Date()))
            sDate.text = root.isoDate(s); sTime.text = Qt.formatTime(s, "HH:mm")
            eDate.text = root.isoDate(allDay.checked ? root.addDays(e, -1) : e); eTime.text = Qt.formatTime(e, "HH:mm")
            repeat.value = ev.repeat || ""
            cal.value = ev.calendar
            title.input.forceActiveFocus()
        }
        readonly property var startDt: root.parse(sDate.text + (allDay.checked ? "" : "T" + sTime.text))
        readonly property var endDt: allDay.checked ? (root.parse(eDate.text) ? root.addDays(root.parse(eDate.text), 1) : null)
                                                    : root.parse(eDate.text + "T" + eTime.text)
        readonly property bool valid: !!startDt && !!endDt && endDt >= startDt
        MouseArea { anchors.fill: parent }   // clicks stay in the pop-over

        ColumnLayout {
            id: form
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 8
            Field { id: title; Layout.fillWidth: true; placeholder: "New Event"; pixelSize: 16 }
            Field { id: location; Layout.fillWidth: true; placeholder: "Add Location" }
            RowLayout {
                spacing: 8
                Rectangle {
                    implicitWidth: 34; implicitHeight: 20; radius: 10
                    color: allDay.checked ? Theme.green : Theme.fgA(0.2)
                    Rectangle { width: 16; height: 16; radius: 8; y: 2; x: allDay.checked ? 16 : 2; color: "white" }
                    MouseArea { id: allDay; property bool checked: false; anchors.fill: parent; onClicked: checked = !checked }
                }
                Text { textFormat: Text.PlainText; text: "All-day"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBody }
            }
            GridLayout {
                columns: 3
                columnSpacing: 8
                rowSpacing: 6
                Text { textFormat: Text.PlainText; text: "Starts"; color: Theme.fgA(0.6); font.family: Theme.fontFamily; font.pixelSize: Theme.fontBody }
                Field { id: sDate; Layout.preferredWidth: 110; placeholder: "yyyy-mm-dd"; valid: !!root.parse(text) }
                Field { id: sTime; Layout.preferredWidth: 70; visible: !allDay.checked; placeholder: "hh:mm"; valid: /^\d{1,2}:\d{2}$/.test(text) }
                Text { textFormat: Text.PlainText; text: "Ends"; color: Theme.fgA(0.6); font.family: Theme.fontFamily; font.pixelSize: Theme.fontBody }
                Field { id: eDate; Layout.preferredWidth: 110; placeholder: "yyyy-mm-dd"; valid: !!root.parse(text) && pop.valid }
                Field { id: eTime; Layout.preferredWidth: 70; visible: !allDay.checked; placeholder: "hh:mm"; valid: /^\d{1,2}:\d{2}$/.test(text) && pop.valid }
            }
            RowLayout {
                spacing: 8
                Text { textFormat: Text.PlainText; text: "Repeat"; color: Theme.fgA(0.6); font.family: Theme.fontFamily; font.pixelSize: Theme.fontBody }
                Choice {
                    id: repeat
                    options: [{ "id": "", "label": "Never" }, { "id": "daily", "label": "Every Day" }, { "id": "weekly", "label": "Every Week" },
                              { "id": "monthly", "label": "Every Month" }, { "id": "yearly", "label": "Every Year" }]
                }
                Choice {
                    id: cal
                    options: root.calendars.map(c => ({ "id": c.id, "label": c.name, "color": c.color }))
                }
            }
            Field { id: notes; Layout.fillWidth: true; placeholder: "Add Notes"; multiline: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                AppButton {
                    visible: !!pop.ev.uid
                    label: pop.ev.repeats ? "Delete This Event" : "Delete"
                    onClicked: root.remove(pop.ev, !!pop.ev.repeats)
                }
                AppButton {
                    visible: !!pop.ev.uid && !!pop.ev.repeats
                    label: "Delete All"
                    onClicked: root.remove(pop.ev, false)
                }
                Item { Layout.fillWidth: true }
                AppButton { label: "Cancel"; onClicked: root.editing = null }
                AppButton {
                    label: "Save"
                    accent: true
                    enabledState: pop.valid
                    onClicked: root.save({
                        "uid": pop.ev.uid || "", "calendar": cal.value, "oldCalendar": pop.ev.oldCalendar || "",
                        "occurrence": pop.ev.repeats ? pop.ev.occurrence : "",
                        "title": title.text, "location": location.text, "notes": notes.text, "allDay": allDay.checked,
                        "repeat": repeat.value, "start": root.iso(pop.startDt), "end": root.iso(pop.endDt) })
                }
            }
        }
    }
}
