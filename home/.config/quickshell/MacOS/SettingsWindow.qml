import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import qs.DockApp

// macOS-style System Settings for the Mac pieces of this desktop.
//   qs ipc call settings open [PANE]     PANE: general, controlcenter, dock,
//                                         displays, wallpaper, sound, lock,
//                                         battery, trackpad, network
// Panes are lists of rows (see paneRows). Each row reads its live value through
// get() and writes through set(), so a row redraws by itself when the setting
// changes. Quickshell-side settings live in MacSettings (settings.json); the
// dock in DockSettings (macos-look/dock.json); the rest go through commands.
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
        dispProc.running = false
        dispProc.running = true
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
            "echo \"wallpaper=$(cat ~/.config/macos-look/wallpaper 2>/dev/null)\";" +
            "for kv in $(~/.local/bin/macos-idle get); do echo \"idle_$kv\"; done;" +
            "echo \"nftables=$(systemctl is-active nftables)\"; echo \"opensnitch=$(systemctl is-active opensnitchd)\";" +
            "echo \"usbguard=$(systemctl is-active usbguard)\";" +
            "busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager" +
            " HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked 2>/dev/null" +
            " | awk '{ gsub(/\"/, \"\", $2); print \"lid_\" NR \"=\" $2 }'"]
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
        command: ["bash", "-c", "find ~/.local/share/macos-look/wallpapers ~/Pictures/Wallpapers -maxdepth 2 -type f "
            + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: root.wallpapers = this.text.split("\n").filter(l => l !== "")
        }
    }

    function run(cmd: var): void { Quickshell.execDetached(cmd) }

    // ==========================================
    // DISPLAYS (arrangement, orientation, resolution, scale)
    // ==========================================
    // Everything goes through ~/.local/bin/macos-displays, which saves it per
    // screen (displays.json) so display-mode.sh re-applies it on hotplug.
    // The built-in panel (eDP, LVDS or DSI); empty on desktops.
    readonly property string laptop: (root.displays.find(m => /^(eDP|LVDS|DSI)-/.test(m.name)) || { "name": "" }).name
    property var displays: []
    property string selDisplay: ""        // description of the selected screen
    property bool arranging: false        // a screen is being dragged

    // Screens with their own place on the desktop, numbered left to right.
    readonly property var shownDisplays: root.displays
        .filter(m => !m.disabled && m.mirrorOf === "none")
        .sort((a, b) => a.x - b.x || a.y - b.y)
    readonly property var selMon: root.shownDisplays.find(m => m.description === root.selDisplay)
        || root.shownDisplays[0] || null

    function displayNumber(desc: string): int {
        return root.shownDisplays.findIndex(m => m.description === desc) + 1
    }
    function displayName(m: var): string {
        return m.name === root.laptop ? "Built-in Display" : (m.model || m.name)
    }

    readonly property string displayMode: {
        const lap = root.displays.find(m => m.name === root.laptop)
        const ext = root.displays.filter(m => m.name !== root.laptop)
        if (ext.length === 0) return "laptop"
        if (lap && lap.disabled) return "external"
        if (ext.every(m => m.disabled)) return "laptop"
        if (ext.some(m => m.mirrorOf !== "none")) return "duplicate"
        return "extend"
    }

    Process {
        id: dispProc
        command: [root.home + "/.local/bin/macos-displays", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.displays = JSON.parse(this.text) } catch (e) { return }
                if (root.pane === "displays" && !root.arranging && root.choiceRow === null)
                    root.sections = root.paneRows(root.pane)
            }
        }
    }
    Timer { id: dispRefresh; interval: 900; onTriggered: { dispProc.running = false; dispProc.running = true } }

    // ==========================================
    // OTHER PANES' DATA (~/.local/bin/macos-prefs, JSON)
    // ==========================================
    // pd.usb, pd.battery, pd.time, pd.notify, pd.printers, pd.login,
    // pd.appearance, pd.zones. A pane showing a list is rebuilt when its data
    // arrives; single values redraw by themselves.
    property var pd: ({})
    readonly property string prefs: root.home + "/.local/bin/macos-prefs"
    readonly property var paneData: ({ "security": "usb", "battery": "battery", "datetime": "time",
        "notifications": "notify", "printers": "printers", "login": "login", "appearance": "appearance" })

    component JsonProc: Process {
        id: jp
        property string key
        stdout: StdioCollector {
            onStreamFinished: {
                let v
                try { v = JSON.parse(this.text) } catch (e) { return }
                let d = Object.assign({}, root.pd)
                d[jp.key] = v
                root.pd = d
                if (root.paneData[root.pane] === jp.key)
                    root.refreshPane()
            }
        }
    }
    JsonProc { id: usbProc;      key: "usb";        command: [root.prefs, "usb"] }
    JsonProc { id: batProc;      key: "battery";    command: [root.prefs, "battery"] }
    JsonProc { id: timeProc;     key: "time";       command: [root.prefs, "time"] }
    JsonProc { id: notifyProc;   key: "notify";     command: [root.prefs, "notify", "get"] }
    JsonProc { id: printProc;    key: "printers";   command: [root.prefs, "printers", "get"] }
    JsonProc { id: loginProc;    key: "login";      command: [root.prefs, "login", "get"] }
    JsonProc { id: appearProc;   key: "appearance"; command: [root.prefs, "appearance", "get"] }

    readonly property var dataProcs: ({ "usb": usbProc, "battery": batProc, "time": timeProc,
        "notify": notifyProc, "printers": printProc, "login": loginProc, "appearance": appearProc })

    function reload(key: string): void {
        const p = root.dataProcs[key]
        if (p) { p.running = false; p.running = true }
    }
    // Run a change, then read the pane's data again once it has landed.
    function change(cmd: var, key: string): void {
        root.run(cmd)
        pendingKey = key
        changeTimer.restart()
    }
    property string pendingKey: ""
    Timer { id: changeTimer; interval: 700; onTriggered: root.reload(root.pendingKey) }

    function refreshPane(): void {
        if (!root.arranging && root.choiceRow === null)
            root.sections = root.paneRows(root.pane)
    }

    // Apps for Notifications and Login Items: launcher-visible desktop entries.
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay && e.name)
        .sort((a, b) => a.name.localeCompare(b.name))
        .filter((e, i, arr) => i === 0 || arr[i - 1].name !== e.name)

    readonly property var commonZones: [
        "America/New_York", "America/Chicago", "America/Denver", "America/Phoenix",
        "America/Los_Angeles", "America/Anchorage", "Pacific/Honolulu", "America/Halifax",
        "America/St_Johns", "America/Toronto", "America/Vancouver", "America/Mexico_City",
        "America/Bogota", "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "UTC",
        "Europe/London", "Europe/Dublin", "Europe/Lisbon", "Europe/Paris", "Europe/Berlin",
        "Europe/Madrid", "Europe/Rome", "Europe/Amsterdam", "Europe/Stockholm", "Europe/Athens",
        "Europe/Istanbul", "Europe/Moscow", "Africa/Cairo", "Africa/Johannesburg", "Africa/Lagos",
        "Asia/Dubai", "Asia/Kolkata", "Asia/Bangkok", "Asia/Singapore", "Asia/Shanghai",
        "Asia/Hong_Kong", "Asia/Tokyo", "Asia/Seoul", "Australia/Perth", "Australia/Sydney",
        "Pacific/Auckland"
    ]

    // USBGuard blocks new USB devices silently. Watch the kernel log and say
    // so, with a button that opens Privacy & Security.
    Process {
        running: true
        command: ["journalctl", "-k", "-f", "-n0", "-o", "cat"]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("not authorized for usage") >= 0) usbNotice.restart() }
        }
    }
    // Rules may still allow the device a moment later; check after the burst.
    Timer {
        id: usbNotice
        interval: 2500
        onTriggered: root.run(["sh", "-c",
            "n=$(\"$HOME/.local/bin/macos-prefs\" usb | jq '[.[] | select(.state == \"block\" and .kind != \"Device\")] | length');" +
            " [ \"${n:-0}\" -gt 0 ] || exit 0;" +
            " a=$(notify-send -a 'Privacy & Security' -i security-high -A open='Review' 'USB accessory blocked'" +
            " \"$n new USB device(s) are blocked until you allow them.\");" +
            " [ \"$a\" = open ] && qs ipc call settings open security"])
    }

    // A change that can leave a screen unreadable (orientation, resolution,
    // scale) asks "Keep these display settings?" and reverts after 15 seconds,
    // like Windows.
    property var revert: null             // { desc, key, value }
    property int revertLeft: 0
    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: { if (--root.revertLeft <= 0) root.revertDisplay() }
    }

    function setDisplay(m: var, key: string, value: var, old: var): void {
        if (`${value}` === `${old}`)
            return
        root.run([root.home + "/.local/bin/macos-displays", "set", m.description, key, `${value}`])
        root.revert = { "desc": m.description, "key": key, "value": `${old}` }
        root.revertLeft = 15
        revertTimer.restart()
        dispRefresh.restart()
    }
    function keepDisplay(): void { revertTimer.stop(); root.revert = null }
    function revertDisplay(): void {
        revertTimer.stop()
        const r = root.revert
        root.revert = null
        if (r) {
            root.run([root.home + "/.local/bin/macos-displays", "set", r.desc, r.key, r.value])
            dispRefresh.restart()
        }
    }

    // Where a dragged screen lands: against the nearest edge of another
    // screen, sharing at least 20 px of that edge, lined up with its top or
    // bottom (left or right) when close, never overlapping.
    function snapDisplay(desc: string, x: real, y: real, w: real, h: real): point {
        const others = root.shownDisplays.filter(m => m.description !== desc)
        if (others.length === 0)
            return Qt.point(0, 0)
        const near = 60
        const overlaps = (cx, cy) => others.some(o =>
            cx < o.x + o.lw && cx + w > o.x && cy < o.y + o.lh && cy + h > o.y)
        let best = null, bestD = Infinity
        others.forEach(o => {
            let ay = Math.max(o.y - h + 20, Math.min(y, o.y + o.lh - 20))
            if (Math.abs(ay - o.y) < near) ay = o.y
            else if (Math.abs(ay + h - o.y - o.lh) < near) ay = o.y + o.lh - h
            let ax = Math.max(o.x - w + 20, Math.min(x, o.x + o.lw - 20))
            if (Math.abs(ax - o.x) < near) ax = o.x
            else if (Math.abs(ax + w - o.x - o.lw) < near) ax = o.x + o.lw - w
            ;[[o.x + o.lw, ay], [o.x - w, ay], [ax, o.y + o.lh], [ax, o.y - h]].forEach(c => {
                const d = Math.hypot(c[0] - x, c[1] - y)
                if (d < bestD && !overlaps(c[0], c[1])) { best = c; bestD = d }
            })
        })
        return best ? Qt.point(Math.round(best[0]), Math.round(best[1])) : Qt.point(x, y)
    }

    function arrangeDisplays(desc: string, x: int, y: int): void {
        let pos = {}
        root.shownDisplays.forEach(m => pos[m.description] = m.description === desc ? [x, y] : [m.x, m.y])
        root.run([root.home + "/.local/bin/macos-displays", "arrange", JSON.stringify(pos)])
        dispRefresh.restart()
    }

    // Identify: a big number in the corner of each screen for three seconds.
    property bool identifying: false
    Timer { id: identifyTimer; interval: 3000; onTriggered: root.identifying = false }
    function identify(): void { root.identifying = true; identifyTimer.restart() }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: idWin
            required property var modelData
            readonly property var mon: root.shownDisplays.find(m => m.name === modelData.name) || null
            screen: modelData
            visible: root.identifying && mon !== null
            anchors { left: true; bottom: true }
            margins { left: 40; bottom: 40 }
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: 180
            implicitHeight: 180
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                radius: 24
                color: Qt.rgba(0.1, 0.1, 0.1, 0.85)
                border.color: Theme.fgA(0.2)
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: idWin.mon ? root.displayNumber(idWin.mon.description) : ""
                    color: "#ffffff"
                    font.family: Theme.displayFamily
                    font.pixelSize: 110
                    font.weight: Font.Bold
                }
            }
        }
    }

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

    // Lid actions go to logind through /usr/local/bin/macos-lid (pkexec, no
    // password). lid_1/2/3 = on battery, plugged in, external display; an empty
    // plugged-in value means "same as on battery".
    function lidAction(n: int): string {
        const v = root.st["lid_" + n] || ""
        return v === "" && n === 2 ? (root.st.lid_1 || "suspend") : v
    }

    function setLid(n: int, action: string): void {
        let v = [root.lidAction(1), root.lidAction(2), root.lidAction(3)]
        v[n - 1] = action
        root.setState("lid_" + n, action)
        root.run(["pkexec", "/usr/local/bin/macos-lid", v[0], v[1], v[2]])
    }

    readonly property var lidChoices: [
        { "id": "ignore",   "label": "Do nothing" }, { "id": "suspend",  "label": "Sleep" },
        { "id": "lock",     "label": "Lock" },       { "id": "poweroff", "label": "Shut down" }
    ]

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
        { "id": "appearance",    "label": "Appearance",        "glyph": "", "color": "#3a3a3c" },
        { "id": "controlcenter", "label": "Control Center",    "glyph": "", "color": "#636366" },
        { "id": "dock",          "label": "Desktop & Dock",    "glyph": "", "color": "#3a3a3c" },
        { "id": "displays",      "label": "Displays",          "glyph": "", "color": "#0a84ff" },
        { "id": "wallpaper",     "label": "Wallpaper",         "glyph": "", "color": "#32ade6" },
        { "id": "notifications", "label": "Notifications",     "glyph": "", "color": "#ff3b30" },
        { "id": "sound",         "label": "Sound",             "glyph": "", "color": "#ff375f" },
        { "id": "lock",          "label": "Lock Screen",       "glyph": "", "color": "#2c2c2e" },
        { "id": "security",      "label": "Privacy & Security", "glyph": "", "color": "#0a84ff" },
        { "id": "login",         "label": "Login Items",       "glyph": "", "color": "#636366" },
        { "id": "battery",       "label": "Battery",           "glyph": "", "color": "#30d158" },
        { "id": "keyboard",      "label": "Keyboard",          "glyph": "", "color": "#8e8e93" },
        { "id": "mouse",         "label": "Mouse",             "glyph": "󰍽", "color": "#8e8e93" },
        { "id": "trackpad",      "label": "Trackpad",          "glyph": "", "color": "#8e8e93" },
        { "id": "printers",      "label": "Printers & Scanners", "glyph": "", "color": "#8e8e93" },
        { "id": "datetime",      "label": "Date & Time",       "glyph": "", "color": "#0a84ff" }
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
                  "action": () => root.run([root.home + "/.local/bin/macos-update"]) },
                { "type": "button", "label": "App Store", "text": "Open…",
                  "action": () => root.run(["flatpak", "run", "io.github.kolunmi.Bazaar"]) }
            ]},
            { "title": "", "rows": [
                { "type": "button", "label": "Keyboard Shortcuts", "text": "Show…",
                  "action": () => root.run([root.home + "/.local/bin/macos-keybinds"]) },
                { "type": "button", "label": "Advanced (Hyprland custom.lua)", "text": "Edit…",
                  "action": () => root.run(["xdg-open", root.home + "/.config/hypr/custom.lua"]) }
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
        if (id === "displays") {
            const secs = [{ "title": "", "rows": [ { "type": "arrangement" } ] }]
            const m = root.selMon
            if (m) {
                // Read the screen fresh: the list is replaced after every change.
                const cur = () => root.displays.find(x => x.description === m.description) || m
                const res = cur => `${cur.width}x${cur.height}`
                const resolutions = [...new Set(m.availableModes.map(s => s.split("@")[0]))]
                    .sort((a, b) => { const [aw, ah] = a.split("x"), [bw, bh] = b.split("x"); return bw * bh - aw * ah })
                const ratesFor = r => [...new Set(m.availableModes.filter(s => s.startsWith(r + "@"))
                    .map(s => parseFloat(s.split("@")[1]).toFixed(2)))].sort((a, b) => b - a)
                const nearest = (list, v) => list.reduce((b, x) => Math.abs(x - v) < Math.abs(b - v) ? x : b, list[0])
                const native = resolutions[0]
                secs.push({ "title": root.displayNumber(m.description) + ". " + root.displayName(m), "rows": [
                    { "type": "choice", "label": "Display orientation",
                      "options": [{ "id": 0, "label": "Landscape" }, { "id": 1, "label": "Portrait" },
                                  { "id": 2, "label": "Landscape (flipped)" }, { "id": 3, "label": "Portrait (flipped)" }],
                      "get": () => cur().transform,
                      "set": v => root.setDisplay(m, "transform", v, cur().transform) },
                    { "type": "choice", "label": "Display resolution",
                      "options": resolutions.map(r => ({ "id": r,
                          "label": r.replace("x", " × ") + (r === native ? " (Recommended)" : "") })),
                      "get": () => res(cur()),
                      "set": v => root.setDisplay(m, "mode", `${v}@${ratesFor(v)[0]}`,
                          `${res(cur())}@${cur().refreshRate.toFixed(2)}`) },
                    { "type": "choice", "label": "Refresh rate",
                      "options": ratesFor(res(m)).map(r => ({ "id": r, "label": parseFloat(r) + " Hz" })),
                      "get": () => nearest(ratesFor(res(cur())), cur().refreshRate),
                      "set": v => root.setDisplay(m, "mode", `${res(cur())}@${v}`,
                          `${res(cur())}@${cur().refreshRate.toFixed(2)}`) },
                    { "type": "choice", "label": "Scale",
                      "options": [1, 1.25, 1.5, 1.75, 2].map(v => ({ "id": v, "label": (v * 100) + "%" })),
                      "get": () => nearest([1, 1.25, 1.5, 1.75, 2], cur().scale),
                      "set": v => root.setDisplay(m, "scale", v, cur().scale) }
                ]})
            }
            if (root.displays.length > 1) secs.push({ "title": "Multiple displays", "rows": [
                { "type": "choice", "label": "Show desktop on",
                  "options": [{ "id": "extend", "label": "Extend these displays" },
                              { "id": "duplicate", "label": "Duplicate these displays" },
                              { "id": "laptop", "label": "Built-in display only" },
                              { "id": "external", "label": "External displays only" }],
                  "get": () => root.displayMode,
                  "set": v => { root.run([root.home + "/.config/hypr/scripts/display-mode.sh", v]); dispRefresh.restart() } }
            ]})
            secs.push({ "title": "", "rows": [
                { "type": "slider", "label": "Brightness", "from": 1, "to": 100,
                  "get": () => Number(root.st.brightness || 50),
                  "set": v => { root.setState("brightness", `${Math.round(v)}`); root.run(["brightnessctl", "set", Math.round(v) + "%"]) } },
                { "type": "switch", "label": "Night Shift", "sub": "Warmer colors after dark",
                  "get": () => root.st.nightshift === "1",
                  "set": on => { root.setState("nightshift", on ? "1" : "0"); root.run([root.home + "/.local/bin/macos-nightshift", on ? "on" : "off"]) } }
            ]})
            return secs
        }
        if (id === "wallpaper") return [
            { "title": "", "rows": [ { "type": "wallpapers" } ] }
        ]
        if (id === "sound") return [
            { "title": "Sound Effects", "rows": [
                { "type": "switch", "label": "Play sound on startup",
                  "get": () => root.st.chime === "enabled",
                  "set": on => { root.setState("chime", on ? "enabled" : "disabled")
                                 root.run(["systemctl", on ? "enable" : "disable", "macos-boot-chime.service"]) } },
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
                  "action": () => root.run([root.home + "/.local/bin/macos-power", "-l"]) }
            ]}
        ]
        if (id === "battery") return [
            { "title": "When I close the lid", "rows": [
                { "type": "choice", "label": "On battery", "options": root.lidChoices,
                  "get": () => root.lidAction(1), "set": v => root.setLid(1, v) },
                { "type": "choice", "label": "Plugged in", "options": root.lidChoices,
                  "get": () => root.lidAction(2), "set": v => root.setLid(2, v) },
                { "type": "choice", "label": "With an external display connected", "options": root.lidChoices,
                  "get": () => root.lidAction(3), "set": v => root.setLid(3, v) }
            ]},
            { "title": "", "rows": [
                { "type": "info", "label": "Built-in display", "value": "Turns off while the lid is closed" }
            ]},
            { "title": "Energy Mode", "rows": [
                { "type": "choice", "label": "Power mode",
                  "options": [{ "id": "power-saver", "label": "Low Power" }, { "id": "balanced", "label": "Balanced" },
                              { "id": "performance", "label": "High Performance" }],
                  "get": () => (root.pd.battery || {}).profile || "balanced",
                  "set": v => root.change(["powerprofilesctl", "set", v], "battery") }
            ]},
            { "title": "Battery Health", "rows": [
                { "type": "info", "label": "Maximum capacity", "sub": "Compared with when it was new",
                  "value": (root.pd.battery || {}).health ? root.pd.battery.health + "%" : "…" },
                { "type": "info", "label": "Cycle count", "value": `${(root.pd.battery || {}).cycles || "…"}` },
                { "type": "choice", "label": "Charge limit", "sub": "Stopping short of full slows battery wear",
                  "options": [{ "id": 100, "label": "Off (charge to 100%)" }, { "id": 90, "label": "90%" },
                              { "id": 80, "label": "80%" }, { "id": 60, "label": "60%" }],
                  "get": () => (root.pd.battery || {}).limit || 100,
                  "set": v => root.change(["pkexec", "/usr/local/bin/macos-admin", "charge-limit", v === 100 ? "off" : `${v}`], "battery") }
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
        if (id === "appearance") return [
            { "title": "", "rows": [
                { "type": "choice", "label": "Appearance",
                  "options": [{ "id": "light", "label": "Light" }, { "id": "dark", "label": "Dark" }],
                  "get": () => MacSettings.get("appearance", "mode"),
                  "set": v => { MacSettings.setAppearance(v); root.refreshPane() } },
                { "type": "accents", "label": "Accent color" },
                { "type": "choice", "label": "Text size",
                  "options": [{ "id": 0.9, "label": "Small" }, { "id": 1, "label": "Default" },
                              { "id": 1.15, "label": "Large" }, { "id": 1.3, "label": "Larger" },
                              { "id": 1.5, "label": "Largest" }],
                  "get": () => (root.pd.appearance || {}).textScale || 1,
                  "set": v => root.change([root.prefs, "appearance", "text-scale", `${v}`], "appearance") }
            ]},
            { "title": "", "rows": [
                { "type": "info", "label": "Qt apps", "value": "Pick up a change when reopened" }
            ]}
        ]
        if (id === "notifications") {
            const n = root.pd.notify || { "dnd": false, "muted": [], "timeout": 4 }
            return [
                { "title": "", "rows": [
                    { "type": "switch", "label": "Do Not Disturb", "sub": "Silence notifications; they still collect in Notification Center",
                      "get": () => !!(root.pd.notify || {}).dnd,
                      "set": on => root.change([root.prefs, "notify", "dnd", on ? "on" : "off"], "notify") },
                    { "type": "choice", "label": "Show banners for",
                      "options": [3, 4, 5, 8, 10, 15].map(t => ({ "id": t, "label": t + " seconds" })),
                      "get": () => (root.pd.notify || {}).timeout || 4,
                      "set": v => root.change([root.prefs, "notify", "timeout", `${v}`], "notify") }
                ]},
                { "title": "Application Notifications", "rows": root.apps.map(e => ({
                    "type": "switch", "label": e.name,
                    "get": () => ((root.pd.notify || {}).muted || []).indexOf(e.name) < 0,
                    "set": on => root.change([root.prefs, "notify", "app", e.name, on ? "on" : "off"], "notify") })) }
            ]
        }
        if (id === "security") {
            const devs = root.pd.usb || []
            const blocked = devs.filter(d => d.state !== "allow")
            const allowed = devs.filter(d => d.state === "allow")
            const devRow = d => ({ "type": d.state === "allow" ? "info" : "button", "label": d.name,
                "sub": d.kind + " · " + d.vid + " · port " + d.port,
                "value": "Allowed", "text": "Allow",
                "action": () => root.change(["pkexec", "/usr/local/bin/macos-usb", "allow", `${d.id}`], "usb") })
            const sw = (g, k, label, sub) => ({ "type": "switch", "label": label, "sub": sub,
                "get": () => MacSettings.get(g, k) === true, "set": on => MacSettings.set(g, k, on) })
            let secs = [
                { "title": "Privacy", "rows": [
                    sw("privacy", "clipboardHistory", "Clipboard history", "Super+V lists what you copied. Password manager copies are never kept"),
                    sw("privacy", "clipboardKeep", "Keep clipboard history after logout", "Off: the history stays in memory only"),
                    sw("privacy", "clipboardImages", "Keep copied images in the history", "Screenshots are copied too"),
                    sw("privacy", "capturePrompt", "Ask before apps capture the screen", "Also before loading other Hyprland plugins. After logging in again"),
                    { "type": "choice", "label": "Apps can set the wallpaper",
                      "options": [{ "id": "ask", "label": "Ask" }, { "id": "never", "label": "Never" }, { "id": "always", "label": "Always" }],
                      "get": () => MacSettings.get("privacy", "wallpaperApps"),
                      "set": v => MacSettings.set("privacy", "wallpaperApps", v) },
                    sw("privacy", "albumArtOnline", "Load album art from the internet", "Now Playing fetches cover images from the player's web addresses")
                ]},
                { "title": "Desktop features", "rows": [
                    sw("features", "appSwitcher", "App switcher", "Super+Tab shows your open apps. Off: Super+Tab opens Mission Control"),
                    sw("features", "windowTiling", "Window tiling", "Window > Move & Resize and Super+Shift+Arrows"),
                    sw("features", "screenRecording", "Screen recording", "Record buttons in the screenshot toolbar (Shift+Super+5)")
                ]}
            ]
            if (devs.length || root.st.usbguard === "active")
                secs.push({ "title": "USB accessories", "rows": [
                    { "type": "info", "label": "USB accessories", "sub": "New devices stay blocked until you allow them here (USBGuard)",
                      "value": blocked.length ? blocked.length + " blocked" : "None blocked" }
                ]})
            if (blocked.length) secs.push({ "title": "Blocked accessories", "rows": blocked.map(devRow) })
            if (allowed.length) secs.push({ "title": "Allowed accessories", "rows": allowed.map(devRow) })
            secs.push({ "title": "Firewall", "rows": [
                { "type": "info", "label": "Network firewall (nftables)",
                  "value": root.st.nftables === "active" ? "On" : "Off" },
                { "type": "button", "label": "Application firewall (OpenSnitch)",
                  "sub": root.st.opensnitch === "active" ? "On: asks before apps connect" : "Off",
                  "text": "Open…", "action": () => root.run(["opensnitch-ui"]) }
            ]})
            return secs
        }
        if (id === "login") {
            const items = root.pd.login || []
            return [
                { "title": "Open at Login", "rows": items.map(i => ({
                    "type": "switch", "label": i.name, "sub": i.system ? "Installed by the system" : "",
                    "get": () => (((root.pd.login || []).find(x => x.file === i.file)) || i).enabled,
                    "set": on => root.change([root.prefs, "login", "set", i.file, on ? "on" : "off"], "login") })) },
                { "title": "", "rows": [
                    { "type": "choice", "label": "Add an app", "options": root.apps.map(e => ({ "id": e.id, "label": e.name })),
                      "get": () => "", "set": v => root.change([root.prefs, "login", "add", v], "login") },
                    { "type": "info", "label": "Changes apply", "value": "At next login" }
                ]}
            ]
        }
        if (id === "keyboard") return [
            { "title": "", "rows": [
                { "type": "slider", "label": "Key repeat rate", "sub": "Slow to fast", "from": 5, "to": 60,
                  "get": () => M.get("keyboard", "repeatRate"),
                  "set": v => { M.set("keyboard", "repeatRate", Math.round(v)); hyprReload.restart() } },
                { "type": "slider", "label": "Delay until repeat", "sub": "Short to long", "from": 150, "to": 1000,
                  "get": () => M.get("keyboard", "repeatDelay"),
                  "set": v => { M.set("keyboard", "repeatDelay", Math.round(v / 50) * 50); hyprReload.restart() } }
            ]},
            { "title": "", "rows": [
                { "type": "choice", "label": "Keyboard layout", "sub": "Alt+Shift switches when there are two",
                  "options": [
                      { "id": "us", "label": "U.S." }, { "id": "us(intl)", "label": "U.S. International" },
                      { "id": "gb", "label": "British" }, { "id": "ca", "label": "Canadian French" },
                      { "id": "de", "label": "German" }, { "id": "fr", "label": "French" },
                      { "id": "es", "label": "Spanish" }, { "id": "latam", "label": "Latin American" },
                      { "id": "it", "label": "Italian" }, { "id": "pt", "label": "Portuguese" },
                      { "id": "br", "label": "Brazilian" }, { "id": "us,es", "label": "U.S. + Spanish" },
                      { "id": "us,de", "label": "U.S. + German" }, { "id": "us,fr", "label": "U.S. + French" }],
                  "get": () => M.get("keyboard", "layout"),
                  "set": v => { M.set("keyboard", "layout", v); hyprReload.restart() } },
                { "type": "choice", "label": "Caps Lock key",
                  "options": [{ "id": "", "label": "Caps Lock" }, { "id": "ctrl:nocaps", "label": "Control" },
                              { "id": "caps:escape", "label": "Escape" }, { "id": "caps:backspace", "label": "Backspace" },
                              { "id": "caps:none", "label": "No Action" }],
                  "get": () => M.get("keyboard", "capsLock"),
                  "set": v => { M.set("keyboard", "capsLock", v); hyprReload.restart() } }
            ]},
            { "title": "", "rows": [
                { "type": "button", "label": "Keyboard Shortcuts", "text": "Show…",
                  "action": () => root.run([root.home + "/.local/bin/macos-keybinds"]) }
            ]}
        ]
        if (id === "mouse") return [
            { "title": "", "rows": [
                { "type": "slider", "label": "Tracking speed", "sub": "Also used by the trackpad", "from": -1, "to": 1,
                  "get": () => M.get("mouse", "speed"),
                  "set": v => { M.set("mouse", "speed", Math.round(v * 20) / 20); hyprReload.restart() } },
                { "type": "switch", "label": "Pointer acceleration", "sub": "Faster movement goes farther",
                  "get": () => M.get("mouse", "acceleration"),
                  "set": on => { M.set("mouse", "acceleration", on); hyprReload.restart() } },
                { "type": "switch", "label": "Natural scrolling", "sub": "Content tracks the wheel like a trackpad",
                  "get": () => M.get("mouse", "naturalScroll"),
                  "set": on => { M.set("mouse", "naturalScroll", on); hyprReload.restart() } },
                { "type": "choice", "label": "Primary mouse button",
                  "options": [{ "id": false, "label": "Left" }, { "id": true, "label": "Right" }],
                  "get": () => M.get("mouse", "leftHanded"),
                  "set": v => { M.set("mouse", "leftHanded", v); hyprReload.restart() } }
            ]}
        ]
        if (id === "printers") {
            const pr = root.pd.printers || { "printers": [], "jobs": 0 }
            let secs = []
            if (pr.printers.length) {
                secs.push({ "title": "Printers", "rows": pr.printers.map(x => ({
                    "type": "info", "label": x.name, "value": x.state.charAt(0).toUpperCase() + x.state.slice(1) })) })
                secs.push({ "title": "", "rows": [
                    { "type": "choice", "label": "Default printer",
                      "options": pr.printers.map(x => ({ "id": x.name, "label": x.name })),
                      "get": () => ((((root.pd.printers || {}).printers || []).find(x => x.default)) || {}).name || "",
                      "set": v => root.change([root.prefs, "printers", "default", v], "printers") },
                    { "type": "info", "label": "Print jobs", "value": pr.jobs ? pr.jobs + " waiting" : "None" }
                ]})
            } else {
                secs.push({ "title": "", "rows": [
                    { "type": "info", "label": "No printers", "value": "Network printers show up here once added" } ] })
            }
            secs.push({ "title": "", "rows": [
                { "type": "button", "label": "Printers and scanners", "text": "Add Printer…",
                  "action": () => root.run(["system-config-printer"]) }
            ]})
            return secs
        }
        if (id === "datetime") {
            const t = root.pd.time || { "zone": "", "ntp": true }
            const zones = root.commonZones.indexOf(t.zone) < 0 && t.zone ? [t.zone].concat(root.commonZones) : root.commonZones
            return [
                { "title": "", "rows": [
                    { "type": "switch", "label": "Set time and date automatically", "sub": "From the internet (NTP)",
                      "get": () => (root.pd.time || {}).ntp !== false,
                      "set": on => root.change(["timedatectl", "set-ntp", on ? "true" : "false"], "time") },
                    { "type": "choice", "label": "Time zone",
                      "options": zones.map(z => ({ "id": z, "label": z.replace(/_/g, " ") })),
                      "get": () => (root.pd.time || {}).zone || "",
                      "set": v => root.change(["timedatectl", "set-timezone", `${v}`], "time") },
                    { "type": "switch", "label": "24-hour time",
                      "get": () => M.get("menubar", "clock24h"), "set": on => M.set("menubar", "clock24h", on) }
                ]}
            ]
        }
        return []
    }

    readonly property bool sinkReady: Pipewire.defaultAudioSink !== null
        && Pipewire.defaultAudioSink.ready && Pipewire.defaultAudioSink.audio !== null
    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }

    property var sections: root.paneRows(root.pane)
    onPaneChanged: {
        root.sections = root.paneRows(root.pane)
        if (root.paneData[root.pane])
            root.reload(root.paneData[root.pane])
    }
    onSelDisplayChanged: root.sections = root.paneRows(root.pane)

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
            // Transparent window: the sidebar is translucent (Hyprland blurs
            // what is behind it) and the content pane paints its own background.
            color: "transparent"
            implicitWidth: 860
            implicitHeight: 680
            onVisibleChanged: if (!visible) root.open = false

            // --- Controls ---
            component MacSwitch: Rectangle {
                id: sw
                property bool checked: false
                signal toggled(bool on)
                implicitWidth: 38
                implicitHeight: 22
                radius: 11
                color: checked ? Theme.accent : Theme.fgA(0.16)
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
                color: mbMouse.pressed ? Theme.fgA(0.28) : Theme.fgA(0.16)
                Text {
                    textFormat: Text.PlainText
                    id: mbText
                    anchors.centerIn: parent
                    text: mb.text
                    color: Theme.fg
                    font.family: Theme.fontFamily
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
                    color: Theme.sidebar
                    topLeftRadius: 12
                    bottomLeftRadius: 12

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
                            color: Theme.fgA(0.08)
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
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                clip: true
                                onTextChanged: root.search = text
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.fill: parent
                                    text: "Search"
                                    color: Theme.fgA(0.4)
                                    font: searchInput.font
                                    visible: searchInput.text === ""
                                }
                            }
                        }

                        // Pane list scrolls when the window is too short for it.
                        Flickable {
                            id: paneList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: paneCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: paneCol
                                width: paneList.width
                                spacing: 2
                                Repeater {
                                    model: root.visiblePanes
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        radius: 6
                                        color: root.pane === modelData.id ? Theme.accent
                                            : (paneMouse.containsMouse ? Theme.fgA(0.06) : "transparent")
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            spacing: 8
                                            Rectangle {
                                                implicitWidth: 22; implicitHeight: 22
                                                radius: 6
                                                color: modelData.color
                                                border.width: modelData.color === "#2c2c2e" || modelData.color === "#3a3a3c" ? 1 : 0
                                                border.color: Theme.fgA(0.15)
                                                Text {
                                                    textFormat: Text.PlainText
                                                    anchors.centerIn: parent
                                                    text: modelData.glyph
                                                    color: "#ffffff"
                                                    font.family: "Symbols Nerd Font"
                                                    font.pixelSize: 12
                                                }
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                text: modelData.label
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
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
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.dark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.12) }

                // ---------- Content ----------
                Flickable {
                    id: content
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        parent: content
                        anchors.fill: parent
                        z: -1
                        color: Theme.window
                        topRightRadius: 12
                        bottomRightRadius: 12
                    }
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
                            textFormat: Text.PlainText
                            text: root.paneTitle
                            color: Theme.fg
                            font.family: Theme.displayFamily
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
                                    textFormat: Text.PlainText
                                    visible: section.modelData.title !== ""
                                    text: section.modelData.title
                                    color: Theme.fgA(0.85)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.leftMargin: 4
                                }

                                // Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: cardCol.implicitHeight
                                    radius: 10
                                    color: Theme.group
                                    border.width: 1
                                    border.color: Theme.fgA(0.06)

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
                                                    : r.type === "arrangement" ? 270
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
                                                    color: Theme.fgA(0.07)
                                                }

                                                // label (+ sub label)
                                                Column {
                                                    visible: rowItem.r.type !== "wallpapers" && rowItem.r.type !== "arrangement"
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 14
                                                    anchors.right: control.left
                                                    anchors.rightMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2
                                                    Text {
                                                        textFormat: Text.PlainText
                                                        width: parent.width
                                                        text: rowItem.r.label || ""
                                                        color: Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        textFormat: Text.PlainText
                                                        visible: !!rowItem.r.sub
                                                        width: parent.width
                                                        text: rowItem.r.sub || ""
                                                        color: Theme.fgA(0.5)
                                                        font.family: Theme.fontFamily
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
                                                            : rowItem.r.type === "info" ? infoComp
                                                            : rowItem.r.type === "accents" ? accentsComp : null
                                                    }
                                                }

                                                Component {
                                                    id: accentsComp
                                                    Row {
                                                        spacing: 8
                                                        Repeater {
                                                            model: Theme.accentOrder
                                                            Rectangle {
                                                                required property string modelData
                                                                readonly property bool current: Theme.accentName === modelData
                                                                width: 18; height: 18; radius: 9
                                                                color: Theme.system(modelData)
                                                                border.width: current ? 2 : 0
                                                                border.color: Theme.fg
                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    onClicked: MacSettings.setAccent(parent.modelData)
                                                                }
                                                            }
                                                        }
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
                                                        textFormat: Text.PlainText
                                                        text: rowItem.r.value
                                                        color: Theme.fgA(0.55)
                                                        font.family: Theme.fontFamily
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
                                                            if (current === "")
                                                                return "Choose…"
                                                            // A value set outside System Settings (e.g. 11 minutes)
                                                            return typeof current === "number" ? root.durationLabel(current) : `${current}`
                                                        }
                                                        implicitWidth: Math.max(120, choiceText.implicitWidth + 36)
                                                        implicitHeight: 24
                                                        radius: 6
                                                        color: Theme.fgA(choiceMouse.pressed ? 0.24 : 0.14)
                                                        Text {
                                                            textFormat: Text.PlainText
                                                            id: choiceText
                                                            anchors.left: parent.left
                                                            anchors.leftMargin: 10
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: choiceBtn.currentLabel
                                                            color: Theme.fg
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 13
                                                        }
                                                        Text {
                                                            textFormat: Text.PlainText
                                                            anchors.right: parent.right
                                                            anchors.rightMargin: 8
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "⌃\n⌄"
                                                            lineHeight: 0.45
                                                            color: Theme.fgA(0.7)
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
                                                            color: Theme.fgA(0.16)
                                                            Rectangle { width: parent.width * slider.frac; height: parent.height; radius: 2; color: Theme.accent }
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

                                                // Display arrangement (displays pane): drag a screen
                                                // to move it, click to select it.
                                                Item {
                                                    id: arrange
                                                    visible: rowItem.r.type === "arrangement"
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    readonly property var mons: visible ? root.shownDisplays : []
                                                    readonly property real minX: Math.min(...mons.map(m => m.x))
                                                    readonly property real minY: Math.min(...mons.map(m => m.y))
                                                    readonly property real bw: Math.max(...mons.map(m => m.x + m.lw)) - minX
                                                    readonly property real bh: Math.max(...mons.map(m => m.y + m.lh)) - minY
                                                    readonly property real area: height - 40
                                                    // Room around the screens to drag one to any side.
                                                    readonly property real f: mons.length ? Math.min((width - 60) / bw, (area - 40) / bh, 0.1) : 1
                                                    readonly property real ox: (width - bw * f) / 2
                                                    readonly property real oy: (area - bh * f) / 2

                                                    Rectangle {
                                                        width: parent.width; height: arrange.area
                                                        radius: 8
                                                        color: Qt.rgba(0, 0, 0, 0.25)
                                                    }

                                                    Repeater {
                                                        model: arrange.mons
                                                        delegate: Rectangle {
                                                            id: screenRect
                                                            required property var modelData
                                                            readonly property bool sel: root.selMon && root.selMon.description === modelData.description
                                                            x: arrange.ox + (modelData.x - arrange.minX) * arrange.f
                                                            y: arrange.oy + (modelData.y - arrange.minY) * arrange.f
                                                            width: modelData.lw * arrange.f
                                                            height: modelData.lh * arrange.f
                                                            radius: 6
                                                            color: sel ? Theme.accent : (Theme.dark ? "#4a4a4e" : "#c7c7cc")
                                                            border.width: 2
                                                            border.color: sel ? Qt.lighter(Theme.accent, 1.3) : Theme.fgA(0.25)
                                                            z: dragArea.drag.active ? 2 : 1
                                                            Column {
                                                                anchors.centerIn: parent
                                                                Text {
                                                                    textFormat: Text.PlainText
                                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                                    text: root.displayNumber(screenRect.modelData.description)
                                                                    color: "#ffffff"
                                                                    font.family: Theme.displayFamily
                                                                    font.pixelSize: 28
                                                                    font.weight: Font.Bold
                                                                }
                                                                Text {
                                                                    textFormat: Text.PlainText
                                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                                    width: Math.min(implicitWidth, screenRect.width - 8)
                                                                    text: root.displayName(screenRect.modelData)
                                                                    color: Theme.fgA(0.8)
                                                                    font.family: Theme.fontFamily
                                                                    font.pixelSize: 10
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                            MouseArea {
                                                                id: dragArea
                                                                anchors.fill: parent
                                                                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                                drag.target: arrange.mons.length > 1 ? screenRect : null
                                                                drag.threshold: 4
                                                                onPressed: root.arranging = true
                                                                onReleased: {
                                                                    // Selecting rebuilds the pane (and this delegate),
                                                                    // so it comes last.
                                                                    const m = screenRect.modelData
                                                                    if (drag.active || screenRect.x !== arrange.ox + (m.x - arrange.minX) * arrange.f) {
                                                                        const p = root.snapDisplay(m.description,
                                                                            (screenRect.x - arrange.ox) / arrange.f + arrange.minX,
                                                                            (screenRect.y - arrange.oy) / arrange.f + arrange.minY, m.lw, m.lh)
                                                                        screenRect.x = arrange.ox + (p.x - arrange.minX) * arrange.f
                                                                        screenRect.y = arrange.oy + (p.y - arrange.minY) * arrange.f
                                                                        if (p.x !== m.x || p.y !== m.y)
                                                                            root.arrangeDisplays(m.description, p.x, p.y)
                                                                    }
                                                                    root.arranging = false
                                                                    root.selDisplay = m.description
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        textFormat: Text.PlainText
                                                        anchors.left: parent.left
                                                        anchors.bottom: parent.bottom
                                                        anchors.bottomMargin: 4
                                                        text: arrange.mons.length > 1 ? "Drag displays to match how they sit on your desk"
                                                            : "Select a display to change its settings"
                                                        color: Theme.fgA(0.5)
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                    }
                                                    MacButton {
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        text: "Identify"
                                                        onClicked: root.identify()
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
                                                                border.color: Theme.accent
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
                                                                        root.run([root.home + "/.local/bin/macos-wallpaper", modelData])
                                                                    }
                                                                }
                                                            }
                                                            Text {
                                                                textFormat: Text.PlainText
                                                                width: (contentCol.width - 24 - 36) / 4
                                                                text: modelData.split("/").pop().replace(/\.[^.]+$/, "").replace(/[-_]/g, " ")
                                                                color: Theme.fgA(0.7)
                                                                font.family: Theme.fontFamily
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

            // ---------- Keep display settings? (drawn over the window) ----------
            Item {
                anchors.fill: parent
                z: 10
                visible: root.revert !== null
                MouseArea { anchors.fill: parent }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
                Rectangle {
                    anchors.centerIn: parent
                    width: 340
                    height: keepCol.implicitHeight + 36
                    radius: 12
                    color: Theme.popup
                    border.color: Theme.fgA(0.14)
                    Column {
                        id: keepCol
                        anchors.centerIn: parent
                        width: parent.width - 36
                        spacing: 8
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: "Keep these display settings?"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: "Reverting to previous display settings in " + root.revertLeft + " seconds."
                            color: Theme.fgA(0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 6
                            spacing: 10
                            MacButton { text: "Revert"; onClicked: root.revertDisplay() }
                            Rectangle {
                                implicitWidth: keepText.implicitWidth + 28
                                implicitHeight: 24
                                radius: 6
                                color: keepMouse.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                                Text {
                                    textFormat: Text.PlainText
                                    id: keepText
                                    anchors.centerIn: parent
                                    text: "Keep changes"
                                    color: Theme.onAccent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                                MouseArea { id: keepMouse; anchors.fill: parent; onClicked: root.keepDisplay() }
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
                    width: 240
                    height: Math.min(choiceList.implicitHeight + 10, 380, overlay.height - 16)
                    radius: 8
                    color: Theme.popup
                    border.color: Theme.fgA(0.14)
                    clip: true

                    // Long lists (apps, time zones) scroll.
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 5
                        contentHeight: choiceList.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: choiceList
                        width: parent.width
                        Repeater {
                            model: root.choiceRow ? root.choiceRow.options : []
                            delegate: Rectangle {
                                required property var modelData
                                width: choiceList.width
                                height: 24
                                radius: 5
                                color: optMouse.containsMouse ? Theme.accent : "transparent"
                                readonly property bool isCurrent: root.choiceRow && root.choiceRow.get() === modelData.id
                                Text {
                                    textFormat: Text.PlainText
                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.isCurrent ? "✓" : ""
                                    color: optMouse.containsMouse ? Theme.onAccent : Theme.fg
                                    font.pixelSize: 12
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    x: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: optMouse.containsMouse ? Theme.onAccent : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: optMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        // Closing the popup destroys this delegate:
                                        // read everything first.
                                        const row = root.choiceRow
                                        const id = modelData.id
                                        root.choiceRow = null
                                        row.set(id)
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
