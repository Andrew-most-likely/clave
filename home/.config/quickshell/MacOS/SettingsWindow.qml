import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs.DockApp

// macOS-style System Settings for the Mac pieces of this desktop.
//   qs ipc call settings open [PANE]     PANE: general, controlcenter, dock,
//                                         displays, wallpaper, sound, lock,
//                                         trackpad, network
// Panes are lists of rows (see paneRows). Each row reads its live value through
// get() and writes through set(), so a row redraws by itself when the setting
// changes. Quickshell-side settings live in MacSettings (settings.json); the
// dock in DockSettings (ml4w-dock/dock.json); the rest go through commands.
Scope {
    id: root

    property bool open: false
    property string pane: "general"
    property string search: ""
    readonly property string home: Quickshell.env("HOME")

    IpcHandler {
        target: "settings"
        function open(pane: string): void {
            if (pane !== "" && root.panes.some(p => p.id === pane))
                root.pane = pane
            root.open = true
            root.probe()
        }
        function close(): void { root.open = false }
        // Scriptable access to the same settings the window edits:
        //   qs ipc call settings set menubar clock24h true
        //   qs ipc call settings get menubar clock24h
        function set(group: string, key: string, value: string): void {
            let v = value
            try { v = JSON.parse(value) } catch (e) {}
            if (group === "dock") {
                if (key === "autohide")
                    DockSettings.setAutohide(!!v)
                else
                    DockSettings.setDockValue(key, v)
            } else if (group === "trackpad") {
                MacSettings.set(group, key, v)
                hyprReload.restart()
            } else if (group === "windows" && key === "trafficLights") {
                root.setTrafficLights(!!v)
            } else {
                MacSettings.set(group, key, v)
            }
        }
        function get(group: string, key: string): string {
            return JSON.stringify(MacSettings.get(group, key))
        }
    }

    // ==========================================
    // SYSTEM STATE (read with commands)
    // ==========================================
    property var st: ({})
    property var wallpapers: []

    function probe(): void {
        statusProc.running = false
        statusProc.running = true
        wallProc.running = false
        wallProc.running = true
    }

    function setState(key: string, value: var): void {
        let s = Object.assign({}, root.st)
        s[key] = value
        root.st = s
    }

    Process {
        id: statusProc
        command: ["bash", "-c",
            "echo \"nightshift=$(pgrep -x hyprsunset >/dev/null && echo 1 || echo 0)\";" +
            "echo \"brightness=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d %)\";" +
            "echo \"wifi=$(nmcli radio wifi 2>/dev/null)\";" +
            "echo \"bt=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')\";" +
            "echo \"chime=$(systemctl is-enabled macos-boot-chime.service 2>/dev/null)\";" +
            "echo \"wallpaper=$(cat ~/.cache/ml4w/hyprland-dotfiles/current_wallpaper 2>/dev/null)\";" +
            "for kv in $(~/.local/bin/macos-idle get); do echo \"idle_$kv\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = {}
                this.text.split("\n").forEach(line => {
                    const i = line.indexOf("=")
                    if (i > 0)
                        s[line.slice(0, i)] = line.slice(i + 1)
                })
                root.st = s
            }
        }
    }

    Process {
        id: wallProc
        command: ["bash", "-c", "find ~/.config/ml4w/wallpapers -maxdepth 2 -type f "
            + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: root.wallpapers = this.text.split("\n").filter(l => l !== "")
        }
    }

    function run(cmd: var): void { Quickshell.execDetached(cmd) }

    // Settings the Hyprland config reads (hypr.lua) apply with a reload,
    // shortly after MacSettings has written the file.
    Timer { id: hyprReload; interval: 300; onTriggered: root.run(["hyprctl", "reload"]) }

    function setTrafficLights(on: bool): void {
        MacSettings.set("windows", "trafficLights", on)
        if (on) {
            hyprReload.restart()
        } else {
            root.run(["sh", "-c", "hyprctl plugin unload \"$HOME/.local/share/macos-look/hyprbars/hyprbars.so\"; sleep 0.3; hyprctl reload"])
        }
    }

    function setIdle(key: string, seconds: int): void {
        let v = { "lock": Number(root.st.idle_lock || 0), "display": Number(root.st.idle_display || 0),
                  "sleep": Number(root.st.idle_sleep || 0) }
        v[key] = seconds
        root.setState("idle_" + key, `${seconds}`)
        root.run([root.home + "/.local/bin/macos-idle", "set", `${v.lock}`, `${v.display}`, `${v.sleep}`])
    }

    function durationLabel(sec: int): string {
        if (sec <= 0)
            return "Never"
        if (sec % 3600 === 0)
            return "For " + (sec / 3600) + (sec === 3600 ? " hour" : " hours")
        const m = Math.round(sec / 60)
        return "For " + m + (m === 1 ? " minute" : " minutes")
    }

    readonly property var idleChoices: [
        { "id": 60, "label": "For 1 minute" }, { "id": 120, "label": "For 2 minutes" },
        { "id": 300, "label": "For 5 minutes" }, { "id": 600, "label": "For 10 minutes" },
        { "id": 1200, "label": "For 20 minutes" }, { "id": 1800, "label": "For 30 minutes" },
        { "id": 3600, "label": "For 1 hour" }, { "id": 10800, "label": "For 3 hours" },
        { "id": 0, "label": "Never" }
    ]

    // ==========================================
    // PANES
    // ==========================================
    readonly property var panes: [
        { "id": "network",       "label": "Wi-Fi & Bluetooth", "glyph": "", "color": "#0a84ff" },
        { "id": "general",       "label": "General",           "glyph": "", "color": "#8e8e93" },
        { "id": "controlcenter", "label": "Control Center",    "glyph": "", "color": "#636366" },
        { "id": "dock",          "label": "Desktop & Dock",    "glyph": "", "color": "#3a3a3c" },
        { "id": "displays",      "label": "Displays",          "glyph": "", "color": "#0a84ff" },
        { "id": "wallpaper",     "label": "Wallpaper",         "glyph": "", "color": "#32ade6" },
        { "id": "sound",         "label": "Sound",             "glyph": "", "color": "#ff375f" },
        { "id": "lock",          "label": "Lock Screen",       "glyph": "", "color": "#2c2c2e" },
        { "id": "trackpad",      "label": "Trackpad",          "glyph": "", "color": "#8e8e93" }
    ]

    readonly property var visiblePanes: root.search === "" ? root.panes
        : root.panes.filter(p => p.label.toLowerCase().indexOf(root.search.toLowerCase()) >= 0)

    readonly property string paneTitle: (root.panes.find(p => p.id === root.pane) || {}).label || ""

    // Sections of the open pane: [{ title, rows: [...] }]. Row types:
    //   switch  { label, sub, get(), set(bool) }
    //   choice  { label, options: [{ id, label }], get(), set(id) }
    //   slider  { label, from, to, get(), set(value) }     set() on release
    //   button  { label, text, action() }
    //   info    { label, value }
    //   wallpapers                                        thumbnail grid
    function paneRows(id: string): var {
        const M = MacSettings
        const D = DockSettings
        if (id === "network") return [
            { "title": "", "rows": [
                { "type": "switch", "label": "Wi-Fi",
                  "get": () => root.st.wifi === "enabled",
                  "set": on => { root.setState("wifi", on ? "enabled" : "disabled"); root.run(["nmcli", "radio", "wifi", on ? "on" : "off"]) } },
                { "type": "button", "label": "Networks and passwords", "text": "Wi-Fi Settings…",
                  "action": () => root.run(["nm-connection-editor"]) }
            ]},
            { "title": "", "rows": [
                { "type": "switch", "label": "Bluetooth",
                  "get": () => root.st.bt === "yes",
                  "set": on => { root.setState("bt", on ? "yes" : "no"); root.run(["bluetoothctl", "power", on ? "on" : "off"]) } },
                { "type": "button", "label": "Devices", "text": "Bluetooth Settings…",
                  "action": () => root.run(["blueman-manager"]) }
            ]}
        ]
        if (id === "general") return [
            { "title": "", "rows": [
                { "type": "button", "label": "About", "text": "About This Mac",
                  "action": () => root.run(["qs", "ipc", "call", "about", "toggle"]) },
                { "type": "button", "label": "Software Update", "text": "Check for Updates…",
                  "action": () => root.run(["bash", "-c", "eval \"$(cat ~/.config/ml4w/settings/installupdates.sh)\""]) },
                { "type": "button", "label": "App Store", "text": "Open…",
                  "action": () => root.run(["flatpak", "run", "io.github.kolunmi.Bazaar"]) }
            ]},
            { "title": "", "rows": [
                { "type": "button", "label": "Keyboard Shortcuts", "text": "Show…",
                  "action": () => root.run([root.home + "/.config/hypr/scripts/keybindings.sh"]) },
                { "type": "button", "label": "Advanced (ML4W dotfiles settings)", "text": "Open…",
                  "action": () => root.run(["ml4w-dotfiles-settings"]) }
            ]}
        ]
        if (id === "controlcenter") return [
            { "title": "Battery", "rows": [
                { "type": "switch", "label": "Show Percentage",
                  "get": () => M.get("menubar", "batteryPercent"), "set": on => M.set("menubar", "batteryPercent", on) }
            ]},
            { "title": "Clock", "rows": [
                { "type": "switch", "label": "Show the day of the week",
                  "get": () => M.get("menubar", "showDay"), "set": on => M.set("menubar", "showDay", on) },
                { "type": "switch", "label": "Show date",
                  "get": () => M.get("menubar", "showDate"), "set": on => M.set("menubar", "showDate", on) },
                { "type": "switch", "label": "Use a 24-hour clock",
                  "get": () => M.get("menubar", "clock24h"), "set": on => M.set("menubar", "clock24h", on) }
            ]}
        ]
        if (id === "dock") {
            const corner = (key, label) => ({
                "type": "choice", "label": label, "options": M.cornerActions,
                "get": () => M.get("hotCorners", key), "set": v => M.set("hotCorners", key, v) })
            return [
                { "title": "Dock", "rows": [
                    { "type": "slider", "label": "Size", "from": 32, "to": 80,
                      "get": () => D.settings.dock.iconSize, "set": v => D.setDockValue("iconSize", Math.round(v)) },
                    { "type": "choice", "label": "Minimize windows using",
                      "options": [{ "id": "genie", "label": "Genie Effect" }, { "id": "scale", "label": "Scale Effect" }],
                      "get": () => M.get("windows", "minimizeEffect"), "set": v => M.set("windows", "minimizeEffect", v) },
                    { "type": "switch", "label": "Automatically hide and show the Dock",
                      "get": () => D.settings.dock.autohide, "set": on => D.setAutohide(on) },
                    { "type": "switch", "label": "Show indicators for open applications",
                      "get": () => D.settings.dock.showIndicators, "set": on => D.setDockValue("showIndicators", on) }
                ]},
                { "title": "Windows", "rows": [
                    { "type": "switch", "label": "Show title bar buttons", "sub": "Red, yellow and green buttons on apps without their own title bar",
                      "get": () => M.get("windows", "trafficLights"), "set": on => root.setTrafficLights(on) }
                ]},
                { "title": "Hot Corners", "rows": [
                    corner("topLeft", "Top left"), corner("topRight", "Top right"),
                    corner("bottomLeft", "Bottom left"), corner("bottomRight", "Bottom right")
                ]}
            ]
        }
        if (id === "displays") return [
            { "title": "", "rows": [
                { "type": "slider", "label": "Brightness", "from": 1, "to": 100,
                  "get": () => Number(root.st.brightness || 50),
                  "set": v => { root.setState("brightness", `${Math.round(v)}`); root.run(["brightnessctl", "set", Math.round(v) + "%"]) } },
                { "type": "switch", "label": "Night Shift", "sub": "Warmer colors after dark",
                  "get": () => root.st.nightshift === "1",
                  "set": on => { root.setState("nightshift", on ? "1" : "0"); root.run([root.home + "/.config/ml4w/scripts/ml4w-toggle-hyprsunset"]) } }
            ]},
            { "title": "", "rows": [
                { "type": "button", "label": "Resolution, scale and arrangement", "text": "Arrange…",
                  "action": () => root.run(["nwg-displays"]) }
            ]}
        ]
        if (id === "wallpaper") return [
            { "title": "", "rows": [ { "type": "wallpapers" } ] }
        ]
        if (id === "sound") return [
            { "title": "Sound Effects", "rows": [
                { "type": "switch", "label": "Play sound on startup",
                  "get": () => root.st.chime === "enabled",
                  "set": on => { root.setState("chime", on ? "enabled" : "disabled")
                                 root.run(["pkexec", "systemctl", on ? "enable" : "disable", "macos-boot-chime.service"]) } },
                { "type": "switch", "label": "Play user interface sound effects",
                  "get": () => M.get("sound", "uiSounds"), "set": on => M.set("sound", "uiSounds", on) }
            ]},
            { "title": "Output", "rows": [
                { "type": "slider", "label": "Output volume", "from": 0, "to": 100,
                  "get": () => root.sinkReady ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) : 0,
                  "set": v => { if (root.sinkReady) { Pipewire.defaultAudioSink.audio.muted = false; Pipewire.defaultAudioSink.audio.volume = v / 100 } } },
                { "type": "button", "label": "Devices and levels", "text": "Sound Settings…",
                  "action": () => root.run(["pavucontrol"]) }
            ]}
        ]
        if (id === "lock") return [
            { "title": "", "rows": [
                { "type": "choice", "label": "Start lock screen when inactive", "options": root.idleChoices,
                  "get": () => Number(root.st.idle_lock || 0), "set": v => root.setIdle("lock", v) },
                { "type": "choice", "label": "Turn display off when inactive", "options": root.idleChoices,
                  "get": () => Number(root.st.idle_display || 0), "set": v => root.setIdle("display", v) },
                { "type": "choice", "label": "Sleep when inactive", "options": root.idleChoices,
                  "get": () => Number(root.st.idle_sleep || 0), "set": v => root.setIdle("sleep", v) }
            ]},
            { "title": "", "rows": [
                { "type": "button", "label": "Lock the screen now", "text": "Lock Screen",
                  "action": () => root.run([root.home + "/.config/ml4w/scripts/ml4w-power", "-l"]) }
            ]}
        ]
        if (id === "trackpad") return [
            { "title": "", "rows": [
                { "type": "switch", "label": "Tap to click", "sub": "Tap with one finger",
                  "get": () => M.get("trackpad", "tapToClick"),
                  "set": on => { M.set("trackpad", "tapToClick", on); hyprReload.restart() } },
                { "type": "switch", "label": "Natural scrolling", "sub": "Content tracks finger movement",
                  "get": () => M.get("trackpad", "naturalScroll"),
                  "set": on => { M.set("trackpad", "naturalScroll", on); hyprReload.restart() } }
            ]},
            { "title": "Gestures", "rows": [
                { "type": "info", "label": "Swipe between Spaces", "value": "Three-finger swipe left or right" },
                { "type": "info", "label": "Mission Control", "value": "Three-finger swipe up" },
                { "type": "info", "label": "Launchpad", "value": "Pinch with four fingers" }
            ]}
        ]
        return []
    }

    readonly property bool sinkReady: Pipewire.defaultAudioSink !== null
        && Pipewire.defaultAudioSink.ready && Pipewire.defaultAudioSink.audio !== null
    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }

    property var sections: root.paneRows(root.pane)
    onPaneChanged: root.sections = root.paneRows(root.pane)

    // ==========================================
    // CHOICE POPUP STATE
    // ==========================================
    property var choiceRow: null        // the row whose popup is open
    property point choicePos: Qt.point(0, 0)

    // ==========================================
    // WINDOW
    // ==========================================
    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: "System Settings"
            color: "#1e1e1e"
            implicitWidth: 860
            implicitHeight: 620
            onVisibleChanged: if (!visible) root.open = false

            // --- Controls ---
            component MacSwitch: Rectangle {
                id: sw
                property bool checked: false
                signal toggled(bool on)
                implicitWidth: 38
                implicitHeight: 22
                radius: 11
                color: checked ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.16)
                Behavior on color { ColorAnimation { duration: 150 } }
                Rectangle {
                    width: 18; height: 18; radius: 9
                    y: 2
                    x: sw.checked ? sw.width - width - 2 : 2
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.checked) }
            }

            component MacButton: Rectangle {
                id: mb
                property string text: ""
                signal clicked()
                implicitWidth: mbText.implicitWidth + 24
                implicitHeight: 24
                radius: 6
                color: mbMouse.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                Text {
                    id: mbText
                    anchors.centerIn: parent
                    text: mb.text
                    color: "#ffffff"
                    font.family: "SF Pro Text"
                    font.pixelSize: 13
                }
                MouseArea { id: mbMouse; anchors.fill: parent; onClicked: mb.clicked() }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ---------- Sidebar ----------
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 230
                    color: "#262628"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 2

                        // Search
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            implicitHeight: 28
                            radius: 7
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Image {
                                id: searchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                source: "icons/search.svg"
                                sourceSize.width: 28; sourceSize.height: 28
                                width: 13; height: 13
                                opacity: 0.5
                            }
                            TextInput {
                                id: searchInput
                                anchors.left: searchIcon.right
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                font.family: "SF Pro Text"
                                font.pixelSize: 13
                                clip: true
                                onTextChanged: root.search = text
                                Text {
                                    anchors.fill: parent
                                    text: "Search"
                                    color: Qt.rgba(1, 1, 1, 0.4)
                                    font: searchInput.font
                                    visible: searchInput.text === ""
                                }
                            }
                        }

                        Repeater {
                            model: root.visiblePanes
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 6
                                color: root.pane === modelData.id ? "#0a84ff"
                                    : (paneMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    spacing: 8
                                    Rectangle {
                                        implicitWidth: 22; implicitHeight: 22
                                        radius: 6
                                        color: modelData.color
                                        border.width: modelData.color === "#2c2c2e" || modelData.color === "#3a3a3c" ? 1 : 0
                                        border.color: Qt.rgba(1, 1, 1, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.glyph
                                            color: "#ffffff"
                                            font.family: "Symbols Nerd Font"
                                            font.pixelSize: 12
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: "#ffffff"
                                        font.family: "SF Pro Text"
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: paneMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { root.choiceRow = null; root.pane = modelData.id }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Qt.rgba(0, 0, 0, 0.5) }

                // ---------- Content ----------
                Flickable {
                    id: content
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: contentCol.implicitHeight + 40
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: contentCol
                        x: 24
                        y: 16
                        width: content.width - 48
                        spacing: 8

                        Text {
                            text: root.paneTitle
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            Layout.bottomMargin: 8
                        }

                        Repeater {
                            model: root.sections
                            delegate: ColumnLayout {
                                id: section
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 6

                                Text {
                                    visible: section.modelData.title !== ""
                                    text: section.modelData.title
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.family: "SF Pro Text"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 4
                                }

                                // Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: cardCol.implicitHeight
                                    radius: 10
                                    color: "#2a2a2c"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.06)

                                    ColumnLayout {
                                        id: cardCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        spacing: 0

                                        Repeater {
                                            model: section.modelData.rows
                                            delegate: Item {
                                                id: rowItem
                                                required property var modelData
                                                required property int index
                                                readonly property var r: modelData
                                                Layout.fillWidth: true
                                                implicitHeight: r.type === "wallpapers" ? wallGrid.implicitHeight + 24
                                                    : (r.sub ? 52 : 40)

                                                // hairline between rows
                                                Rectangle {
                                                    visible: rowItem.index > 0
                                                    anchors.top: parent.top
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    height: 1
                                                    color: Qt.rgba(1, 1, 1, 0.07)
                                                }

                                                // label (+ sub label)
                                                Column {
                                                    visible: rowItem.r.type !== "wallpapers"
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 14
                                                    anchors.right: control.left
                                                    anchors.rightMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2
                                                    Text {
                                                        width: parent.width
                                                        text: rowItem.r.label || ""
                                                        color: "#ffffff"
                                                        font.family: "SF Pro Text"
                                                        font.pixelSize: 13
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        visible: !!rowItem.r.sub
                                                        width: parent.width
                                                        text: rowItem.r.sub || ""
                                                        color: Qt.rgba(1, 1, 1, 0.5)
                                                        font.family: "SF Pro Text"
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                // control on the right
                                                Item {
                                                    id: control
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 14
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    implicitWidth: loader.item ? loader.item.implicitWidth : 0
                                                    implicitHeight: loader.item ? loader.item.implicitHeight : 0
                                                    width: implicitWidth
                                                    height: implicitHeight
                                                    Loader {
                                                        id: loader
                                                        sourceComponent: rowItem.r.type === "switch" ? switchComp
                                                            : rowItem.r.type === "choice" ? choiceComp
                                                            : rowItem.r.type === "slider" ? sliderComp
                                                            : rowItem.r.type === "button" ? buttonComp
                                                            : rowItem.r.type === "info" ? infoComp : null
                                                    }
                                                }

                                                Component {
                                                    id: switchComp
                                                    MacSwitch {
                                                        checked: rowItem.r.get()
                                                        onToggled: on => rowItem.r.set(on)
                                                    }
                                                }
                                                Component {
                                                    id: buttonComp
                                                    MacButton {
                                                        text: rowItem.r.text
                                                        onClicked: rowItem.r.action()
                                                    }
                                                }
                                                Component {
                                                    id: infoComp
                                                    Text {
                                                        text: rowItem.r.value
                                                        color: Qt.rgba(1, 1, 1, 0.55)
                                                        font.family: "SF Pro Text"
                                                        font.pixelSize: 13
                                                    }
                                                }
                                                Component {
                                                    id: choiceComp
                                                    Rectangle {
                                                        id: choiceBtn
                                                        readonly property var current: rowItem.r.get()
                                                        readonly property string currentLabel: {
                                                            const o = rowItem.r.options.find(o => o.id === current)
                                                            if (o)
                                                                return o.label
                                                            // A value set outside System Settings (e.g. 11 minutes)
                                                            return typeof current === "number" ? root.durationLabel(current) : `${current}`
                                                        }
                                                        implicitWidth: Math.max(120, choiceText.implicitWidth + 36)
                                                        implicitHeight: 24
                                                        radius: 6
                                                        color: Qt.rgba(1, 1, 1, choiceMouse.pressed ? 0.24 : 0.14)
                                                        Text {
                                                            id: choiceText
                                                            anchors.left: parent.left
                                                            anchors.leftMargin: 10
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: choiceBtn.currentLabel
                                                            color: "#ffffff"
                                                            font.family: "SF Pro Text"
                                                            font.pixelSize: 13
                                                        }
                                                        Text {
                                                            anchors.right: parent.right
                                                            anchors.rightMargin: 8
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "⌃\n⌄"
                                                            lineHeight: 0.45
                                                            color: Qt.rgba(1, 1, 1, 0.7)
                                                            font.pixelSize: 9
                                                        }
                                                        MouseArea {
                                                            id: choiceMouse
                                                            anchors.fill: parent
                                                            onClicked: {
                                                                const p = choiceBtn.mapToItem(overlay, 0, choiceBtn.height + 4)
                                                                root.choicePos = Qt.point(p.x, p.y)
                                                                root.choiceRow = rowItem.r
                                                            }
                                                        }
                                                    }
                                                }
                                                Component {
                                                    id: sliderComp
                                                    Item {
                                                        id: slider
                                                        implicitWidth: 260
                                                        implicitHeight: 22
                                                        readonly property real from: rowItem.r.from
                                                        readonly property real to: rowItem.r.to
                                                        property bool dragging: false
                                                        property real dragValue: 0
                                                        readonly property real value: dragging ? dragValue : rowItem.r.get()
                                                        readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))
                                                        Rectangle {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width; height: 4; radius: 2
                                                            color: Qt.rgba(1, 1, 1, 0.16)
                                                            Rectangle { width: parent.width * slider.frac; height: parent.height; radius: 2; color: "#0a84ff" }
                                                        }
                                                        Rectangle {
                                                            width: 20; height: 20; radius: 10
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: slider.frac * (slider.width - width)
                                                            color: "#ffffff"
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            function valueAt(mx: real): real {
                                                                return slider.from + Math.max(0, Math.min(1, mx / slider.width)) * (slider.to - slider.from)
                                                            }
                                                            onPressed: mouse => { slider.dragValue = valueAt(mouse.x); slider.dragging = true }
                                                            onPositionChanged: mouse => slider.dragValue = valueAt(mouse.x)
                                                            onReleased: { rowItem.r.set(slider.dragValue); slider.dragging = false }
                                                        }
                                                    }
                                                }

                                                // Wallpaper grid (wallpaper pane)
                                                Grid {
                                                    id: wallGrid
                                                    visible: rowItem.r.type === "wallpapers"
                                                    x: 12; y: 12
                                                    columns: 4
                                                    spacing: 12
                                                    Repeater {
                                                        model: rowItem.r.type === "wallpapers" ? root.wallpapers : []
                                                        delegate: Column {
                                                            required property string modelData
                                                            spacing: 4
                                                            Rectangle {
                                                                width: (contentCol.width - 24 - 36) / 4
                                                                height: width * 0.62
                                                                radius: 8
                                                                color: "#111111"
                                                                border.width: root.st.wallpaper === modelData ? 3 : 0
                                                                border.color: "#0a84ff"
                                                                clip: true
                                                                Image {
                                                                    anchors.fill: parent
                                                                    anchors.margins: parent.border.width
                                                                    source: "file://" + modelData
                                                                    sourceSize.width: 320
                                                                    sourceSize.height: 200
                                                                    fillMode: Image.PreserveAspectCrop
                                                                    asynchronous: true
                                                                }
                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        root.setState("wallpaper", modelData)
                                                                        root.run([root.home + "/.config/ml4w/scripts/ml4w-wallpaper", modelData, "--skip-theming"])
                                                                    }
                                                                }
                                                            }
                                                            Text {
                                                                width: (contentCol.width - 24 - 36) / 4
                                                                text: modelData.split("/").pop().replace(/\.[^.]+$/, "").replace(/[-_]/g, " ")
                                                                color: Qt.rgba(1, 1, 1, 0.7)
                                                                font.family: "SF Pro Text"
                                                                font.pixelSize: 11
                                                                elide: Text.ElideRight
                                                                horizontalAlignment: Text.AlignHCenter
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

            // ---------- Choice popup (drawn over the window) ----------
            Item {
                id: overlay
                anchors.fill: parent
                visible: root.choiceRow !== null

                MouseArea { anchors.fill: parent; onClicked: root.choiceRow = null }

                Rectangle {
                    x: Math.min(root.choicePos.x, overlay.width - width - 8)
                    y: Math.min(root.choicePos.y, overlay.height - height - 8)
                    width: 210
                    height: choiceList.implicitHeight + 10
                    radius: 8
                    color: "#2f2f31"
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    Column {
                        id: choiceList
                        x: 5; y: 5
                        width: parent.width - 10
                        Repeater {
                            model: root.choiceRow ? root.choiceRow.options : []
                            delegate: Rectangle {
                                required property var modelData
                                width: choiceList.width
                                height: 24
                                radius: 5
                                color: optMouse.containsMouse ? "#0a84ff" : "transparent"
                                readonly property bool isCurrent: root.choiceRow && root.choiceRow.get() === modelData.id
                                Text {
                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.isCurrent ? "✓" : ""
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                }
                                Text {
                                    x: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: "#ffffff"
                                    font.family: "SF Pro Text"
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: optMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        const row = root.choiceRow
                                        root.choiceRow = null
                                        row.set(modelData.id)
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
