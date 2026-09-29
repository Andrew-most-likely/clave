import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts

// Screenshots and screen recording (PROJECT_PLAN.md SHELL-1).
//   qs ipc call screenshot screen     whole focused screen
//   qs ipc call screenshot area       drag a rectangle
//   qs ipc call screenshot toolbar    the toolbar               (Print)
//   qs ipc call screenshot window     click a window
//   qs ipc call screenshot text       copy the text in an area  (Shift+Print)
//   qs ipc call screenshot stop       stop a recording
// Engines: grim (capture), slurp (area and window picking), wf-recorder
// (Recorder.qml), satty (markup) and tesseract (text). Each runs with a fixed
// argument list; file names and areas are passed as arguments, never as
// shell text. Nothing runs while no capture is in progress (PERF-3).
// Options live in settings.json "screenshots": saveTo (pictures, desktop,
// documents, clipboard), folder (for pictures), timer, thumbnail, pointer.
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property bool recordingAllowed: ClaveSettings.get("features", "screenRecording") !== false

    property bool toolbarOpen: false
    property bool optionsOpen: false
    property string mode: "area"           // screen, window, area, record-screen, record-area
    property var job: null                 // { kind, file, clip }
    property int countdown: 0

    IpcHandler {
        target: "screenshot"
        function screen(): void { root.start("screen", false) }
        function area(): void { root.start("area", false) }
        function window(): void { root.start("window", false) }
        function text(): void { root.start("text", false) }
        function toolbar(): void {
            if (Recorder.recording) { Recorder.stop(); return }
            root.optionsOpen = false
            root.toolbarOpen = true
        }
        function stop(): void { Recorder.stop() }
    }

    function opt(key: string): var { return ClaveSettings.get("screenshots", key) }
    function setOpt(key: string, v: var): void { ClaveSettings.set("screenshots", key, v) }

    function folder(): string {
        const to = root.opt("saveTo")
        if (to === "desktop") return root.home + "/Desktop"
        if (to === "documents") return root.home + "/Documents"
        const f = `${root.opt("folder") || ""}`
        return f === "" ? root.home + "/Pictures/Screenshots" : f.replace(/^~(?=\/|$)/, root.home)
    }

    // start(KIND, FROM_TOOLBAR): the toolbar's timer applies only to captures
    // started from the toolbar.
    function start(kind: string, fromToolbar: bool): void {
        if (root.job !== null)
            return
        if (kind.startsWith("record") && (!root.recordingAllowed || Recorder.recording))
            return
        const rec = kind.startsWith("record")
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' HH.mm.ss")
        const clip = !rec && kind !== "text" && root.opt("saveTo") === "clipboard"
        const dir = clip ? root.runtimeDir : root.folder()
        const name = clip ? "clave-screenshot.png" : (rec ? "Screen Recording " : "Screenshot ") + stamp + (rec ? ".mp4" : ".png")
        root.job = { "kind": kind, "file": dir + "/" + name, "clip": clip }
        root.toolbarOpen = false
        mkdir.command = ["mkdir", "-p", dir]
        mkdir.running = true
        root.countdown = fromToolbar ? (root.opt("timer") || 0) : 0
        // Let the toolbar disappear before anything is captured.
        delay.interval = root.countdown > 0 ? 1000 : 250
        delay.restart()
    }
    Process { id: mkdir }
    Timer {
        id: delay
        onTriggered: {
            if (root.countdown > 1) { root.countdown--; delay.restart(); return }
            root.countdown = 0
            root.pick()
        }
    }

    // Step 2: where to capture.
    function pick(): void {
        const k = root.job.kind
        if (k === "screen" || k === "record-screen") {
            const m = Hyprland.focusedMonitor
            if (!m) { root.job = null; return }
            root.shoot(["-o", m.name])
        } else if (k === "window") {
            windows.running = true
        } else {
            slurp.boxes = ""
            slurp.stdinEnabled = false
            slurp.command = ["slurp", "-d", "-b", "#00000040", "-c", "#ffffffcc", "-w", "1"]
            slurp.running = true
        }
    }

    // Windows on the visible workspaces, as slurp boxes: a click picks one.
    Process {
        id: windows
        command: ["sh", "-c", "hyprctl -j monitors; echo '#'; hyprctl -j clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("\n#\n")
                    const shown = JSON.parse(parts[0]).map(m => m.activeWorkspace.id)
                    const boxes = JSON.parse(parts[1])
                        .filter(c => c.mapped && !c.hidden && shown.indexOf(c.workspace.id) >= 0
                                && c.class !== "org.quickshell")
                        .map(c => `${c.at[0]},${c.at[1]} ${c.size[0]}x${c.size[1]}`)
                    slurp.boxes = boxes.join("\n") + "\n"
                    slurp.stdinEnabled = true
                    slurp.command = ["slurp", "-r", "-b", "#00000040", "-c", "#ffffffcc", "-B", "#ffffff18", "-w", "1"]
                    slurp.running = true
                } catch (e) {
                    console.warn("screenshot: cannot list windows:", e)
                    root.job = null
                }
            }
        }
    }
    Process {
        id: slurp
        property string boxes: ""
        // Window boxes go in on stdin, then stdin closes so slurp starts.
        onRunningChanged: if (running && boxes !== "") { write(boxes); stdinEnabled = false }
        stdout: StdioCollector { id: slurpOut }
        onExited: code => {
            const geom = slurpOut.text.trim()
            if (code !== 0 || !/^-?\d+,-?\d+ \d+x\d+$/.test(geom)) { root.job = null; return }
            root.shoot(["-g", geom])
        }
    }

    // Step 3: capture, record or read text.
    function shoot(where: var): void {
        const j = root.job
        if (j.kind.startsWith("record")) {
            Recorder.start(where, j.file)
            root.job = null
        } else if (j.kind === "text") {
            ocr.command = ["sh", "-c", "grim \"$1\" \"$2\" - | tesseract stdin stdout 2>/dev/null", "sh", where[0], where[1]]
            ocr.running = true
        } else {
            grim.command = ["grim", ...(root.opt("pointer") ? ["-c"] : []), ...where, j.file]
            grim.running = true
        }
    }
    Process {
        id: grim
        onExited: code => {
            const j = root.job
            root.job = null
            if (code !== 0 || !j)
                return
            Quickshell.execDetached([root.home + "/.local/bin/clave-sound", "screen-capture"])
            Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", j.file])
            if (root.opt("thumbnail") !== false || j.clip)
                root.showThumb(j.file)
        }
    }
    Process {
        id: ocr
        stdout: StdioCollector { id: ocrOut }
        onExited: {
            root.job = null
            const t = ocrOut.text.trim()
            if (t === "") {
                Quickshell.execDetached(["notify-send", "-a", "Screenshot", "No text found"])
                return
            }
            Quickshell.execDetached(["wl-copy", "--", t])
            Quickshell.execDetached(["notify-send", "-a", "Screenshot", "Text copied", t.slice(0, 120)])
        }
    }

    // A saved recording: a notice with "Show in Files".
    Connections {
        target: Recorder
        function onFinished(file: string): void {
            Quickshell.execDetached(["sh", "-c",
                "a=$(notify-send -a 'Screen Recording' -i video-x-generic -A show='Show in Files' 'Screen recording saved' \"${1##*/}\");" +
                " [ \"$a\" = show ] && nautilus --select \"$1\"", "sh", file])
        }
    }

    // ==========================================
    // FLOATING THUMBNAIL
    // ==========================================
    property string thumbFile: ""
    property int thumbSerial: 0
    function showThumb(file: string): void {
        root.thumbFile = file
        root.thumbSerial++
        thumbTimer.restart()
    }
    Timer { id: thumbTimer; interval: 5000; onTriggered: root.thumbFile = "" }
    function markUp(): void {
        const f = root.thumbFile
        root.thumbFile = ""
        Quickshell.execDetached(["satty", "--filename", f, "--output-filename", f, "--copy-command", "wl-copy"])
    }

    LazyLoader {
        active: root.thumbFile !== ""
        PanelWindow {
            screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
            WlrLayershell.namespace: "clave-screenshot-thumbnail"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { bottom: true; right: true }
            margins { bottom: 20; right: 20 }
            exclusiveZone: 0
            implicitWidth: 220
            implicitHeight: thumb.paintedHeight > 0 ? thumb.paintedHeight + 8 : 140
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.panel
                border.color: Theme.fgA(0.2)
                Image {
                    id: thumb
                    anchors.fill: parent
                    anchors.margins: 4
                    source: root.thumbFile === "" ? "" : "file://" + root.thumbFile + "?" + root.thumbSerial
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    sourceSize.width: 440
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: thumbTimer.stop()
                    onExited: thumbTimer.restart()
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton && !root.thumbFile.startsWith(root.runtimeDir)) {
                            Quickshell.execDetached(["nautilus", "--select", root.thumbFile])
                            root.thumbFile = ""
                        } else {
                            root.markUp()
                        }
                    }
                }
            }
        }
    }

    // A countdown in the middle of the screen while the timer runs.
    LazyLoader {
        active: root.countdown > 0
        PanelWindow {
            WlrLayershell.namespace: "clave-screenshot-timer"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0
            implicitWidth: 120
            implicitHeight: 120
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                radius: 24
                color: Theme.panel
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: `${root.countdown}`
                    color: Theme.fg
                    font.family: Theme.displayFamily
                    font.pixelSize: 56
                    font.weight: Font.Medium
                }
            }
        }
    }

    // ==========================================
    // TOOLBAR (Print)
    // ==========================================
    readonly property var modes: [
        { "id": "screen", "label": "Capture Entire Screen", "glyph": "screen" },
        { "id": "window", "label": "Capture Selected Window", "glyph": "window" },
        { "id": "area", "label": "Capture Selected Portion", "glyph": "area" },
        { "id": "record-screen", "label": "Record Entire Screen", "glyph": "screen", "rec": true },
        { "id": "record-area", "label": "Record Selected Portion", "glyph": "area", "rec": true }
    ]
    readonly property var saveOptions: [
        { "id": "pictures", "label": "Screenshots folder" }, { "id": "desktop", "label": "Desktop" },
        { "id": "documents", "label": "Documents" }, { "id": "clipboard", "label": "Clipboard" }
    ]

    // One mode button: a small drawing of what it captures.
    component ModeButton: Rectangle {
        id: mb
        required property var entry
        readonly property bool on: root.mode === entry.id
        implicitWidth: 38
        implicitHeight: 32
        radius: Theme.radiusControl
        color: on ? Theme.fgA(0.22) : mbMouse.containsMouse ? Theme.fgA(0.1) : "transparent"
        Rectangle {           // screen or window outline
            anchors.centerIn: parent
            width: 20; height: 14
            radius: 2
            color: "transparent"
            border.width: 1.5
            border.color: Theme.fg
            visible: mb.entry.glyph !== "area"
            Rectangle {       // window title bar
                visible: mb.entry.glyph === "window"
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 4
                color: Theme.fg
            }
        }
        Canvas {              // dashed rectangle for a portion
            anchors.centerIn: parent
            width: 22; height: 16
            visible: mb.entry.glyph === "area"
            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.strokeStyle = Theme.fg
                c.lineWidth = 1.5
                c.setLineDash([2.5, 2])
                c.strokeRect(1, 1, width - 2, height - 2)
            }
        }
        Rectangle {           // red dot on record modes
            visible: !!mb.entry.rec
            width: 7; height: 7; radius: 4
            color: Theme.red
            anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
        }
        MouseArea {
            id: mbMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.mode = mb.entry.id
        }
        ToolTipText { visible: mbMouse.containsMouse; text: mb.entry.label }
    }
    component ToolTipText: Rectangle {
        property alias text: tt.text
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: tt.implicitWidth + 14
        height: 22
        radius: 6
        color: Theme.tooltip
        z: 10
        Text {
            id: tt
            textFormat: Text.PlainText
            anchors.centerIn: parent
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
        }
    }
    component MenuRow: Rectangle {
        id: mr
        property string label
        property bool checked: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: Theme.menuRowHeight
        radius: Theme.radiusRow
        color: mrMouse.containsMouse ? Theme.accent : "transparent"
        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: (mr.checked ? "✓  " : "     ") + mr.label
            color: mrMouse.containsMouse ? Theme.onAccent : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
        }
        MouseArea { id: mrMouse; anchors.fill: parent; hoverEnabled: true; onClicked: mr.picked() }
    }
    component MenuHeading: Text {
        textFormat: Text.PlainText
        Layout.leftMargin: 6
        Layout.topMargin: 4
        color: Theme.fgA(0.5)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSecondary
        font.weight: Font.DemiBold
    }

    LazyLoader {
        active: root.toolbarOpen
        PanelWindow {
            id: bar
            screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
            WlrLayershell.namespace: "clave-screenshot-toolbar"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors { bottom: true }
            margins { bottom: 80 }
            exclusiveZone: 0
            implicitWidth: Math.max(toolbar.implicitWidth, root.optionsOpen ? 520 : 0) + 20
            implicitHeight: toolbar.implicitHeight + (root.optionsOpen ? options.implicitHeight + 8 : 0) + 20
            color: "transparent"

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.toolbarOpen = false
                Keys.onReturnPressed: root.start(root.mode, true)
                Keys.onEnterPressed: root.start(root.mode, true)

                // Options menu, above the toolbar.
                Rectangle {
                    id: options
                    visible: root.optionsOpen
                    anchors.bottom: toolbarBg.top
                    anchors.bottomMargin: 8
                    anchors.right: toolbarBg.right
                    width: 220
                    implicitHeight: optCol.implicitHeight + 12
                    radius: Theme.radiusMenu
                    color: Theme.menu
                    border.color: Theme.fgA(0.15)
                    ColumnLayout {
                        id: optCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                        spacing: 0
                        MenuHeading { text: "Save to" }
                        Repeater {
                            model: root.saveOptions
                            MenuRow {
                                required property var modelData
                                label: modelData.label
                                checked: (root.opt("saveTo") || "pictures") === modelData.id
                                onPicked: root.setOpt("saveTo", modelData.id)
                            }
                        }
                        MenuHeading { text: "Timer" }
                        Repeater {
                            model: [{ "s": 0, "label": "None" }, { "s": 5, "label": "5 Seconds" }, { "s": 10, "label": "10 Seconds" }]
                            MenuRow {
                                required property var modelData
                                label: modelData.label
                                checked: (root.opt("timer") || 0) === modelData.s
                                onPicked: root.setOpt("timer", modelData.s)
                            }
                        }
                        MenuHeading { text: "Options" }
                        MenuRow {
                            label: "Show Floating Thumbnail"
                            checked: root.opt("thumbnail") !== false
                            onPicked: root.setOpt("thumbnail", !checked)
                        }
                        MenuRow {
                            label: "Show Mouse Pointer"
                            checked: !!root.opt("pointer")
                            onPicked: root.setOpt("pointer", !checked)
                        }
                    }
                }

                Rectangle {
                    id: toolbarBg
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: toolbar.implicitWidth
                    height: toolbar.implicitHeight
                    radius: 12
                    color: Theme.panel
                    border.color: Theme.fgA(0.15)

                    RowLayout {
                        id: toolbar
                        anchors.centerIn: parent
                        spacing: 4
                        Item { implicitWidth: 4 }
                        Rectangle {            // close
                            implicitWidth: 22; implicitHeight: 22; radius: 11
                            color: closeMouse.containsMouse ? Theme.fgA(0.25) : Theme.fgA(0.14)
                            Text { anchors.centerIn: parent; text: "×"; color: Theme.fg; font.pixelSize: 15 }
                            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.toolbarOpen = false }
                        }
                        Item { implicitWidth: 4 }
                        Repeater {
                            model: root.modes.filter(m => !m.rec)
                            ModeButton { required property var modelData; entry: modelData }
                        }
                        Rectangle { visible: root.recordingAllowed; implicitWidth: 1; implicitHeight: 24; color: Theme.fgA(0.2) }
                        Repeater {
                            model: root.recordingAllowed ? root.modes.filter(m => m.rec) : []
                            ModeButton { required property var modelData; entry: modelData }
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 24; color: Theme.fgA(0.2) }
                        Rectangle {            // Options
                            implicitWidth: optText.implicitWidth + 20
                            implicitHeight: 28
                            radius: Theme.radiusControl
                            color: root.optionsOpen ? Theme.fgA(0.22) : optMouse.containsMouse ? Theme.fgA(0.1) : "transparent"
                            Text {
                                id: optText
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: "Options ▾"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                            }
                            MouseArea { id: optMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.optionsOpen = !root.optionsOpen }
                        }
                        Rectangle {            // Capture / Record
                            implicitWidth: capText.implicitWidth + 24
                            implicitHeight: 28
                            radius: Theme.radiusControl
                            color: capMouse.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent
                            Text {
                                id: capText
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: root.mode.startsWith("record") ? "Record" : "Capture"
                                color: Theme.onAccent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                            }
                            MouseArea { id: capMouse; anchors.fill: parent; onClicked: root.start(root.mode, true) }
                        }
                        Item { implicitWidth: 6 }
                    }
                }
            }
        }
    }
}
