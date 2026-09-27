import Quickshell
import Quickshell.Io
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

// Contacts (PROJECT_PLAN.md APP-8): a list with a letter index and a card.
// One .vcf file per contact in ~/.local/share/clave/contacts, read and written
// by clave-pim (python-vobject); this file only draws. No sync, no accounts,
// no network.
FloatingWindow {
    id: root
    title: "Contacts"
    color: Theme.window
    implicitWidth: 820
    implicitHeight: 600
    onVisibleChanged: if (!visible) Qt.quit()

    readonly property string pim: Quickshell.env("HOME") + "/.local/bin/clave-pim"
    property var contacts: []
    property string selected: ""
    property string query: ""
    property bool editing: false
    property string error: ""

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase()
        if (q === "") return root.contacts
        return root.contacts.filter(c => [c.name, c.org].concat((c.emails || []).map(e => e.value), (c.phones || []).map(p => p.value))
            .some(v => `${v}`.toLowerCase().indexOf(q) >= 0))
    }
    readonly property var current: root.contacts.find(c => c.id === root.selected) || null
    function letter(c: var): string {
        const k = (c.family || c.name || "#").trim().charAt(0).toUpperCase()
        return /[A-Z]/.test(k) ? k : "#"
    }

    Process {
        id: load
        running: true
        command: [root.pim, "contacts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.contacts = JSON.parse(this.text) } catch (e) { return }
                if (!root.current && root.contacts.length) root.selected = root.contacts[0].id
            }
        }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }
    function reload(): void { load.running = false; load.running = true }

    Process {
        id: saver
        property string payload: ""
        stdinEnabled: true
        onRunningChanged: if (running && payload !== "") { write(payload); stdinEnabled = false }
        stdout: StdioCollector {
            onStreamFinished: { try { root.selected = JSON.parse(this.text).id } catch (e) {} }
        }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
        onExited: { saver.payload = ""; saver.stdinEnabled = true; root.reload() }
    }
    Process {
        id: action
        onExited: root.reload()
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.error = this.text.trim() }
    }

    function startNew(): void {
        root.selected = ""
        root.editing = true
        card.fill({ "given": "", "family": "", "org": "", "emails": [], "phones": [], "birthday": "", "notes": "" })
    }
    function save(): void {
        saver.payload = JSON.stringify(card.collect(root.editing && root.current ? root.current.id : ""))
        saver.stdinEnabled = true
        saver.command = [root.pim, "contact-save"]
        saver.running = true
        root.editing = false
    }
    function remove(): void {
        if (!root.current) return
        action.command = [root.pim, "contact-delete", root.current.id]
        action.running = true
        root.selected = ""
    }

    FileDialog {
        id: importDialog
        title: "Import contacts"
        nameFilters: ["Contacts (*.vcf *.vcard)"]
        onAccepted: {
            action.command = [root.pim, "import", decodeURIComponent(`${selectedFile}`.replace(/^file:\/\//, ""))]
            action.running = true
        }
    }

    Shortcut { sequence: "Ctrl+N"; onActivated: root.startNew() }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // List
        Rectangle {
            Layout.preferredWidth: 280
            Layout.fillHeight: true
            color: Theme.sidebar
            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 36
                spacing: 6
                SearchField {
                    id: search
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    placeholder: "Search"
                    onTextChanged: root.query = text
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.filtered
                        section.property: "family"
                        section.criteria: ViewSection.FirstCharacter
                        delegate: Column {
                            id: item
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            readonly property bool head: index === 0 || root.letter(root.filtered[index - 1]) !== root.letter(modelData)
                            Text {
                                visible: item.head
                                textFormat: Text.PlainText
                                leftPadding: 14
                                topPadding: 6
                                text: root.letter(item.modelData)
                                color: Theme.fgA(0.5)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                width: parent.width - 12
                                x: 6
                                height: 28
                                radius: Theme.radiusRow
                                color: root.selected === item.modelData.id ? Theme.accent : "transparent"
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    text: item.modelData.given || item.modelData.family
                                        ? (item.modelData.given + " " + item.modelData.family).trim() : item.modelData.name
                                    color: root.selected === item.modelData.id ? Theme.onAccent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBody
                                }
                                MouseArea { anchors.fill: parent; onClicked: { root.editing = false; root.selected = item.modelData.id } }
                            }
                        }
                    }
                    // Letter index: jumps to the first contact with that letter.
                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                        Repeater {
                            model: "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".split("")
                            Text {
                                required property string modelData
                                textFormat: Text.PlainText
                                text: modelData
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const i = root.filtered.findIndex(c => root.letter(c) >= modelData)
                                        if (i >= 0) list.positionViewAtIndex(i, ListView.Beginning)
                                    }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.margins: 8
                    spacing: 4
                    AppButton { label: "+"; tip: "New Contact (Ctrl+N)"; onClicked: root.startNew() }
                    AppButton { label: "Import…"; tip: "Copy a .vcf file into Contacts"; onClicked: importDialog.open() }
                }
            }
        }
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.fgA(0.1) }

        // Card
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: card.implicitHeight + 60
            ColumnLayout {
                id: card
                x: 40
                y: 40
                width: parent.width - 80
                spacing: 12
                visible: root.editing || root.current !== null

                property var emails: []
                property var phones: []
                function fill(c: var): void {
                    given.text = c.given || ""
                    family.text = c.family || ""
                    org.text = c.org || ""
                    birthday.text = c.birthday || ""
                    notes.text = c.notes || ""
                    card.emails = (c.emails || []).map(e => ({ "label": e.label, "value": e.value })).concat([{ "label": "home", "value": "" }])
                    card.phones = (c.phones || []).map(p => ({ "label": p.label, "value": p.value })).concat([{ "label": "cell", "value": "" }])
                }
                function collect(id: string): var {
                    return { "id": id, "given": given.text, "family": family.text, "org": org.text,
                             "emails": card.emails.filter(e => e.value.trim() !== ""),
                             "phones": card.phones.filter(p => p.value.trim() !== ""),
                             "birthday": birthday.text.trim(), "notes": notes.text }
                }
                Connections {
                    target: root
                    function onSelectedChanged(): void { if (root.current) card.fill(root.current) }
                    function onEditingChanged(): void { if (root.editing && root.current) card.fill(root.current) }
                }

                RowLayout {
                    spacing: 16
                    Rectangle {
                        implicitWidth: 72; implicitHeight: 72; radius: 36
                        color: Theme.fgA(0.2)
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: ((given.text || " ").charAt(0) + (family.text || " ").charAt(0)).trim().toUpperCase()
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.Medium
                        }
                    }
                    ColumnLayout {
                        spacing: 4
                        Text {
                            visible: !root.editing
                            textFormat: Text.PlainText
                            text: root.current ? root.current.name : ""
                            color: Theme.fg
                            font.family: Theme.displayFamily
                            font.pixelSize: 24
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: !root.editing && !!root.current && root.current.org !== ""
                            textFormat: Text.PlainText
                            text: root.current ? root.current.org : ""
                            color: Theme.fgA(0.6)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                        }
                        RowLayout {
                            visible: root.editing
                            Field { id: given; placeholder: "First"; Layout.preferredWidth: 150 }
                            Field { id: family; placeholder: "Last"; Layout.preferredWidth: 150 }
                        }
                        Field { id: org; visible: root.editing; placeholder: "Company"; Layout.preferredWidth: 306 }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.fgA(0.1) }

                // Phone numbers and email addresses
                Repeater {
                    model: [["phones", "phone"], ["emails", "email"]]
                    ColumnLayout {
                        id: grp
                        required property var modelData
                        spacing: 6
                        Repeater {
                            model: card[grp.modelData[0]]
                            RowLayout {
                                required property var modelData
                                required property int index
                                visible: root.editing || modelData.value !== ""
                                spacing: 10
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.preferredWidth: 80
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.label + " " + grp.modelData[1]
                                    color: Theme.fgA(0.55)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }
                                Text {
                                    visible: !root.editing
                                    textFormat: Text.PlainText
                                    text: modelData.value
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBody
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Quickshell.execDetached(["xdg-open",
                                            (grp.modelData[1] === "email" ? "mailto:" : "tel:") + modelData.value])
                                    }
                                }
                                Field {
                                    visible: root.editing
                                    Layout.preferredWidth: 240
                                    text: modelData.value
                                    placeholder: grp.modelData[1]
                                    onEdited: {
                                        const list = card[grp.modelData[0]]
                                        list[index].value = text
                                        // A new empty row once the last one is used.
                                        if (index === list.length - 1 && text !== "")
                                            card[grp.modelData[0]] = list.concat([{ "label": grp.modelData[1] === "email" ? "home" : "cell", "value": "" }])
                                    }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    visible: root.editing || birthday.text !== ""
                    spacing: 10
                    Text {
                        textFormat: Text.PlainText
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                        text: "birthday"
                        color: Theme.fgA(0.55)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSecondary
                    }
                    Text {
                        visible: !root.editing
                        textFormat: Text.PlainText
                        text: birthday.text
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                    }
                    Field { id: birthday; visible: root.editing; placeholder: "yyyy-mm-dd"; Layout.preferredWidth: 120 }
                }
                RowLayout {
                    visible: root.editing || notes.text !== ""
                    spacing: 10
                    Text {
                        textFormat: Text.PlainText
                        Layout.preferredWidth: 80
                        Layout.alignment: Qt.AlignTop
                        horizontalAlignment: Text.AlignRight
                        text: "note"
                        color: Theme.fgA(0.55)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSecondary
                    }
                    Text {
                        visible: !root.editing
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: notes.text
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                    }
                    Field { id: notes; visible: root.editing; multiline: true; Layout.preferredWidth: 320 }
                }
                Text {
                    visible: root.error !== ""
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.error
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSecondary
                }
                RowLayout {
                    spacing: 6
                    Layout.topMargin: 10
                    AppButton {
                        visible: !root.editing && !!root.current
                        label: "Delete"
                        enabledState: !!root.current && !root.current.readOnly
                        onClicked: root.remove()
                    }
                    Item { Layout.fillWidth: true }
                    AppButton { visible: root.editing; label: "Cancel"; onClicked: { root.editing = false; if (root.current) card.fill(root.current) } }
                    AppButton {
                        label: root.editing ? "Done" : "Edit"
                        accent: root.editing
                        enabledState: root.editing || (!!root.current && !root.current.readOnly)
                        tip: !root.editing && root.current && root.current.readOnly ? "Part of a file with several contacts" : ""
                        onClicked: root.editing ? root.save() : (root.editing = true)
                    }
                }
            }
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: !card.visible
                text: root.contacts.length ? "No Contact Selected" : "No Contacts"
                color: Theme.fgA(0.4)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitle
            }
        }
    }
}
