import Quickshell
import Quickshell.Io
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel

// Notes (PROJECT_PLAN.md APP-9). Notes are Markdown files in ~/Documents/Notes,
// one folder per folder in the sidebar. Qt's own text document reads and
// writes the Markdown (TextDocument source and save), so there is no web
// engine and no parser of Clave's. Search looks only inside the notes folder.
// Runs as its own process (clave-notes.qml) and exits when the window closes.
FloatingWindow {
    id: root
    title: "Notes"
    color: Theme.window
    implicitWidth: 960
    implicitHeight: 620
    onVisibleChanged: if (!visible) { root.saveNow(); Qt.quit() }

    readonly property string home: Quickshell.env("HOME")
    readonly property string base: root.home + "/Documents/Notes"
    property string folder: root.base          // the folder shown
    property string file: ""                   // the note being edited (path)
    property string query: ""
    property var matches: null                 // paths matching the search, or null
    property bool showSource: false

    function url(p: string): string { return "file://" + p.split("/").map(encodeURIComponent).join("/") }
    function stamp(): string { return Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' HH.mm.ss") }
    function titleOf(name: string): string { return name.replace(/\.md$/i, "") }

    Process { id: mkBase; running: true; command: ["mkdir", "-p", root.base] }

    FolderListModel {
        id: folders
        folder: root.url(root.base)
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }
    FolderListModel {
        id: notes
        folder: root.url(root.folder)
        nameFilters: ["*.md", "*.markdown", "*.txt"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    // Search: grep -l with the words as a fixed string, in this folder only.
    Process {
        id: grep
        stdout: StdioCollector {
            onStreamFinished: root.matches = this.text.split("\n").filter(l => l !== "")
        }
    }
    onQueryChanged: {
        if (root.query.trim() === "") { root.matches = null; return }
        grep.running = false
        grep.command = ["grep", "-rilF", "--include=*.md", "--include=*.markdown", "--include=*.txt",
                        "--", root.query.trim(), root.base]
        grep.running = true
    }

    // ---------------------------------------------------------------- actions
    function open(path: string): void {
        if (path === root.file) return
        root.saveNow()
        root.renameIfNew()
        root.file = path
    }
    function saveNow(): void {
        saveTimer.stop()
        if (root.file !== "" && editor.textDocument.modified)
            editor.textDocument.save()
    }
    // "New Note …" files take their name from the first line when left.
    function renameIfNew(): void {
        const f = root.file
        if (f === "" || !/\/New Note [^/]*\.md$/.test(f)) return
        const first = editor.getText(0, Math.min(editor.length, 200)).split("\n")[0]
            .replace(/[#*_`~>]/g, "").replace(/[\/\\:\0]/g, "-").trim().slice(0, 60)
        if (first === "") return
        mv.command = ["mv", "-n", "--", f, f.slice(0, f.lastIndexOf("/") + 1) + first + ".md"]
        mv.running = true
    }
    Process { id: mv }
    Process { id: touch; onExited: code => { if (code === 0) root.file = root.pending } }
    property string pending: ""
    function newNote(): void {
        root.saveNow()
        root.renameIfNew()
        root.pending = root.folder + "/New Note " + root.stamp() + ".md"
        touch.command = ["touch", "--", root.pending]
        touch.running = true
    }
    Process { id: mkdir }
    function newFolder(): void {
        let n = 1, name = "New Folder"
        while (Array.from({ length: folders.count }, (_, i) => folders.get(i, "fileName")).indexOf(name) >= 0)
            name = "New Folder " + (++n)
        mkdir.command = ["mkdir", "--", root.base + "/" + name]
        mkdir.running = true
    }
    Process { id: trash }
    function deleteNote(): void {
        if (root.file === "") return
        saveTimer.stop()
        trash.command = ["gio", "trash", "--", root.file]
        trash.running = true
        root.file = ""
    }
    function format(prop: string): void {
        const s = editor.cursorSelection
        if (!s || editor.selectedText === "") return
        const f = s.font
        f[prop] = !f[prop]
        s.font = f
    }
    function toggleSource(): void {
        root.saveNow()
        root.showSource = !root.showSource
        const f = root.file
        root.file = ""
        root.file = f
    }

    Timer { id: saveTimer; interval: 800; onTriggered: root.saveNow() }

    Shortcut { sequence: "Ctrl+N"; onActivated: root.newNote() }
    Shortcut { sequence: "Ctrl+B"; onActivated: root.format("bold") }
    Shortcut { sequence: "Ctrl+I"; onActivated: root.format("italic") }
    Shortcut { sequence: "Ctrl+S"; onActivated: root.saveNow() }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }

    // ---------------------------------------------------------------- layout
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Folders
        Rectangle {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            color: Theme.sidebar
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 2
                Text {
                    textFormat: Text.PlainText
                    text: "Folders"
                    color: Theme.fgA(0.5)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSecondary
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 4
                    Layout.topMargin: 30
                }
                Repeater {
                    model: [{ "name": "Notes", "path": root.base }].concat(
                        Array.from({ length: folders.count }, (_, i) =>
                            ({ "name": folders.get(i, "fileName"), "path": root.base + "/" + folders.get(i, "fileName") })))
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.radiusRow
                        color: root.folder === modelData.path ? Theme.fgA(0.14) : "transparent"
                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▢  " + modelData.name
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { root.saveNow(); root.renameIfNew(); root.file = ""; root.folder = modelData.path }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                AppButton { label: "+ New Folder"; onClicked: root.newFolder() }
            }
        }
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.fgA(0.1) }

        // Note list
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.topMargin: 36
                SearchField {
                    id: search
                    Layout.fillWidth: true
                    placeholder: "Search all notes"
                    onTextChanged: root.query = text
                }
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: notes
                delegate: Rectangle {
                    id: row
                    required property string fileName
                    required property string filePath
                    required property date fileModified
                    readonly property bool shown: root.matches === null || root.matches.indexOf(filePath) >= 0
                    width: ListView.view.width
                    height: shown ? 52 : 0
                    visible: shown
                    color: root.file === filePath ? Theme.accent : "transparent"
                    radius: Theme.radiusRow
                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: root.titleOf(row.fileName)
                            elide: Text.ElideRight
                            color: root.file === row.filePath ? Theme.onAccent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: Qt.formatDateTime(row.fileModified, "d MMM yyyy, HH:mm")
                            color: root.file === row.filePath ? Theme.onAccent : Theme.fgA(0.55)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.open(row.filePath) }
                }
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: notes.count === 0
                    text: "No Notes"
                    color: Theme.fgA(0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitle
                }
            }
        }
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.fgA(0.1) }

        // Editor
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                Layout.topMargin: 34
                spacing: 4
                AppButton { label: "✎ New"; tip: "New Note (Ctrl+N)"; onClicked: root.newNote() }
                AppButton { label: "Delete"; enabledState: root.file !== ""; tip: "Move to Trash"; onClicked: root.deleteNote() }
                Item { Layout.fillWidth: true }
                AppButton { label: "B"; tip: "Bold (Ctrl+B)"; enabledState: root.file !== "" && !root.showSource; onClicked: root.format("bold") }
                AppButton { label: "I"; tip: "Italic (Ctrl+I)"; enabledState: root.file !== "" && !root.showSource; onClicked: root.format("italic") }
                AppButton { label: "S"; tip: "Strikethrough"; enabledState: root.file !== "" && !root.showSource; onClicked: root.format("strikeout") }
                AppButton {
                    label: "Aa"
                    active: root.showSource
                    tip: root.showSource ? "Show Formatting" : "Show Markdown (headings, lists, links)"
                    enabledState: root.file !== ""
                    onClicked: root.toggleSource()
                }
            }
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: editor.implicitHeight + 40
                visible: root.file !== ""
                TextEdit {
                    id: editor
                    x: 28
                    y: 12
                    width: flick.width - 56
                    wrapMode: TextEdit.Wrap
                    textFormat: root.showSource ? TextEdit.PlainText : TextEdit.MarkdownText
                    selectByMouse: true
                    persistentSelection: true
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    font.family: root.showSource ? "JetBrains Mono" : Theme.fontFamily
                    font.pixelSize: 15
                    textDocument.source: root.file === "" ? "" : root.url(root.file)
                    onTextChanged: if (textDocument.modified) saveTimer.restart()
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + y < flick.contentY) flick.contentY = cursorRectangle.y + y - 10
                        else if (cursorRectangle.y + y + cursorRectangle.height > flick.contentY + flick.height)
                            flick.contentY = cursorRectangle.y + y + cursorRectangle.height - flick.height + 10
                    }
                    Component.onCompleted: forceActiveFocus()
                }
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.file === ""
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "Select a note, or press Ctrl+N for a new one."
                color: Theme.fgA(0.4)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
            }
        }
    }
}
