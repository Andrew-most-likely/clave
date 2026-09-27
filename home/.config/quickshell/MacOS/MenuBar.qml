import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs.DockApp

// macOS-style menu bar: Apple menu, active app name and its menus, status
// menus (battery, Wi-Fi, sound) and the clock. Replaces the
// StatusbarWindow in shell.qml.
//
// Every title opens a real dropdown. App menus act on the window that was
// focused when the menu opened: they send it the Linux equivalent of the macOS
// shortcut (Hyprland send_shortcut) or run a Hyprland dispatcher. Items with no
// sensible equivalent are shown disabled, the way macOS greys them out.
PanelWindow {
    id: root

    // shell.qml creates one menu bar per screen; only the primary one owns the IPC target.
    property bool primary: true

    WlrLayershell.namespace: "macos-menubar"
    WlrLayershell.layer: WlrLayer.Top

    anchors { top: true; left: true; right: true }
    implicitHeight: 30
    exclusiveZone: 30
    color: Qt.rgba(0, 0, 0, 0.25)

    readonly property string fontFamily: "SF Pro Text"
    readonly property color fg: "#ffffff"
    readonly property color accent: "#0a84ff"
    readonly property string home: Quickshell.env("HOME")
    readonly property var hiddenTrayIds: ["nm-applet", "blueman"]

    // ==========================================
    // ACTIVE APP
    // ==========================================
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property string activeAppId: activeWindow && activeWindow.appId ? activeWindow.appId : ""
    readonly property bool isFinder: activeAppId === "" || activeAppId === "org.gnome.Nautilus"
    readonly property var terminalIds: ["kitty", "Alacritty", "foot", "org.wezfurlong.wezterm",
        "com.mitchellh.ghostty", "org.gnome.Terminal", "org.gnome.Ptyxis", "org.kde.konsole"]
    readonly property bool isTerminal: terminalIds.indexOf(activeAppId) !== -1
    readonly property string appName: {
        if (root.isFinder)
            return "Finder"
        // Shell windows (System Settings, Force Quit…) are named by their title.
        if (root.activeAppId === "org.quickshell" && ToplevelManager.activeToplevel)
            return ToplevelManager.activeToplevel.title
        const entry = DesktopEntries.heuristicLookup(root.activeAppId)
        const name = entry && entry.name ? entry.name : root.activeAppId.split(".").pop()
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    // ==========================================
    // ACTIONS
    // ==========================================
    function hypr(lua: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", lua])
    }

    // Hyprland window address with the 0x prefix, or "".
    function addressOf(ht: var): string {
        const a = ht && ht.address ? `${ht.address}` : ""
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a)
    }

    function hyprToplevels(): var {
        return Hyprland.toplevels.values
    }

    // Sends a key combination to the menu's target window.
    function sendKeys(mods: string, key: string): void {
        const a = root.menuTarget.address
        root.hypr(`hl.dsp.send_shortcut({ mods = "${mods}", key = "${key}"`
            + (a ? `, window = "address:${a}"` : "") + " })")
    }

    // Runs hl.dsp.window.<name> on the window the open menu belongs to.
    function windowDispatch(name: string, args: string): void {
        const a = root.menuTarget.address
        const parts = []
        if (args !== "")
            parts.push(args)
        if (a)
            parts.push(`window = "address:${a}"`)
        root.hypr(`hl.dsp.window.${name}({ ${parts.join(", ")} })`)
    }

    // Window > Center. Hyprland only centers floating windows, and windows
    // tile here, so a tiled window is floated first.
    function centerWindow(): void {
        const a = root.menuTarget.address
        if (!a)
            return
        Quickshell.execDetached(["sh", "-c",
            `hyprctl dispatch 'hl.dsp.window.float({ action = "enable", window = "address:${a}" })'`
            + ` && hyprctl dispatch 'hl.dsp.window.center({ window = "address:${a}" })'`])
    }

    // Menu bar clock, formatted per System Settings > Control Center > Clock.
    function clockText(date: var): string {
        const day = MacSettings.get("menubar", "showDay")
        const showDate = MacSettings.get("menubar", "showDate")
        let d = ""
        if (day && showDate) d = Qt.formatDateTime(date, "ddd MMM d")
        else if (showDate) d = Qt.formatDateTime(date, "MMM d")
        else if (day) d = Qt.formatDateTime(date, "ddd")
        const time = Qt.formatDateTime(date, MacSettings.get("menubar", "clock24h") ? "HH:mm" : "h:mm AP")
        return d === "" ? time : d + "  " + time
    }

    function moveWindow(address: string, workspace: string): void {
        if (address)
            root.hypr(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "address:${address}" })`)
    }

    // Minimized and hidden windows wait on a special workspace; the dock and
    // "Show All" bring them back. Hide moves windows straight there, as macOS
    // hides without an animation; Window > Minimize goes through Minimizer for
    // the genie animation.
    function minimize(address: string): void {
        root.moveWindow(address, "special:minimized")
    }

    function isMinimized(ht: var): bool {
        return ht.workspace !== null && ht.workspace.name === "special:minimized"
    }

    function hideApp(appId: string): void {
        const list = root.hyprToplevels()
        for (let i = 0; i < list.length; i++)
            if (list[i].wayland && list[i].wayland.appId === appId && !root.isMinimized(list[i]))
                root.minimize(root.addressOf(list[i]))
    }

    function hideOthers(appId: string): void {
        const current = Hyprland.focusedWorkspace
        const list = root.hyprToplevels()
        for (let i = 0; i < list.length; i++)
            if (list[i].wayland && list[i].wayland.appId !== appId && list[i].workspace === current)
                root.minimize(root.addressOf(list[i]))
    }

    function showAll(): void {
        const current = Hyprland.focusedWorkspace
        if (!current)
            return
        const list = root.hyprToplevels()
        for (let i = 0; i < list.length; i++)
            if (root.isMinimized(list[i]))
                root.moveWindow(root.addressOf(list[i]), `${current.id}`)
    }

    function appWindows(appId: string): var {
        return ToplevelManager.toplevels.values.filter(t => t.appId === appId)
    }

    function quitApp(appId: string): void {
        const list = root.appWindows(appId)
        for (let i = 0; i < list.length; i++)
            list[i].close()
    }

    function openFolder(path: string): void {
        Quickshell.execDetached(["nautilus", "--new-window", path])
    }

    // ==========================================
    // MENU STATE
    // ==========================================
    // The window the open menu acts on, captured when the menu opens.
    property var menuTarget: ({ "appId": "", "name": "", "address": "", "finder": true, "terminal": false })
    property string openMenu: ""
    property var menuModel: []
    property real menuX: 0
    property bool popupShown: false

    function snapshotTarget(): var {
        return {
            "appId": root.activeAppId,
            "name": root.appName,
            "address": root.addressOf(Hyprland.activeToplevel),
            "finder": root.isFinder,
            "terminal": root.isTerminal
        }
    }

    function openMenuFor(id: string, item: Item): void {
        const switching = root.openMenu !== ""
        if (!switching)
            root.menuTarget = root.snapshotTarget()
        root.openMenu = id
        root.menuModel = root.menuEntries(id)
        // Refresh status data once per opening. The processes rebuild the menu
        // when they finish, so menuEntries() must not start them itself or
        // the menu rebuilds in a loop and hover highlights flicker.
        if (id === "battery")
            powerProfileProc.running = true
        else if (id === "wifi")
            wifiScan.running = true
        root.menuX = item.mapToItem(null, 0, 0).x
        // Switching menus while one is open moves the popup in place instead of
        // hiding and reshowing it, so hovering across titles does not blink.
        if (switching)
            Qt.callLater(() => { if (root.openMenu === id) menuPopup.anchor.updateAnchor() })
        else
            root.popupShown = true
    }

    function toggleMenu(id: string, item: Item): void {
        if (root.openMenu === id)
            root.closeMenu()
        else
            root.openMenuFor(id, item)
    }

    function closeMenu(): void {
        root.popupShown = false
        root.openMenu = ""
    }

    function run(cmd: var): void {
        root.closeMenu()
        Quickshell.execDetached(cmd)
    }

    function findTitle(id: string): var {
        const rows = [leftRow, rightRow]
        for (let r = 0; r < rows.length; r++)
            for (let i = 0; i < rows[r].children.length; i++)
                if (rows[r].children[i].menuId === id)
                    return rows[r].children[i]
        return null
    }

    // qs ipc call menubar open File
    IpcHandler {
        target: "menubar"
        enabled: root.primary
        function open(id: string): void {
            const item = root.findTitle(id)
            if (item)
                root.openMenuFor(id, item)
        }
        function close(): void { root.closeMenu() }
        function isOpen(): string { return root.openMenu }
    }

    // ==========================================
    // MENU CONTENTS
    // ==========================================
    // Entry types:
    //   item    { label, hint, action, enabled (default true), checked }
    //   sep
    //   title   { label, detail }            bold heading of a status menu
    //   header  { label }                    small grey section heading
    //   toggle  { label, get(), set(bool) }  heading with a switch
    //   slider  { get(), set(real) }
    function menuEntries(id: string): var {
        const t = root.menuTarget
        const name = t.name
        const term = t.terminal
        const finder = t.finder

        if (id === "apple") return [
            { "label": "About This Mac", "action": () => root.run(["qs", "ipc", "call", "about", "toggle"]) },
            { "type": "sep" },
            { "label": "System Settings…", "action": () => root.run(["qs", "ipc", "call", "settings", "open", "general"]) },
            { "label": "App Store…", "action": () => root.run(["flatpak", "run", "io.github.kolunmi.Bazaar"]) },
            { "type": "sep" },
            { "label": "Force Quit…", "hint": "⌥⌘⎋", "action": () => root.run(["qs", "ipc", "call", "forcequit", "open"]) },
            { "type": "sep" },
            { "label": "Sleep", "action": () => root.run([root.home + "/.local/bin/macos-power", "-s"]) },
            { "label": "Restart…", "action": () => root.run([root.home + "/.local/bin/macos-power", "-r"]) },
            { "label": "Shut Down…", "action": () => root.run([root.home + "/.local/bin/macos-power", "-p"]) },
            { "type": "sep" },
            { "label": "Lock Screen", "hint": "⌃⌘Q", "action": () => root.run([root.home + "/.local/bin/macos-power", "-l"]) },
            { "label": "Log Out " + Quickshell.env("USER") + "…", "hint": "⇧⌘Q", "action": () => root.run([root.home + "/.local/bin/macos-power", "-e"]) }
        ]

        if (id === "app") return [
            { "label": "About " + name, "enabled": t.appId !== "", "action": () => root.run(["qs", "ipc", "call", "appinfo", "about", t.appId]) },
            { "type": "sep" },
            { "label": "Settings…", "hint": "⌘,", "enabled": t.appId !== "",
              "action": () => term ? root.sendKeys("CTRL SHIFT", "F2") : root.sendKeys("CTRL", "comma") },
            { "type": "sep" },
            { "label": "Hide " + name, "hint": "⌘H", "enabled": t.appId !== "", "action": () => root.hideApp(t.appId) },
            { "label": "Hide Others", "hint": "⌥⌘H", "action": () => root.hideOthers(t.appId) },
            { "label": "Show All", "action": () => root.showAll() },
            { "type": "sep" },
            { "label": "Quit " + name, "hint": "⌘Q", "enabled": !finder, "action": () => root.quitApp(t.appId) }
        ]

        if (id === "File") {
            if (finder) return [
                { "label": "New Finder Window", "hint": "⌘N", "action": () => root.openFolder(root.home) },
                { "label": "New Folder", "hint": "⇧⌘N", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL SHIFT", "N") },
                { "label": "New Tab", "hint": "⌘T", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "T") },
                { "type": "sep" },
                { "label": "Close Window", "hint": "⌘W", "enabled": t.appId !== "", "action": () => root.windowDispatch("close", "") },
                { "type": "sep" },
                { "label": "Get Info", "hint": "⌘I", "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Return") },
                { "label": "Rename", "enabled": t.appId !== "", "action": () => root.sendKeys("", "F2") },
                { "type": "sep" },
                { "label": "Move to Trash", "hint": "⌘⌫", "enabled": t.appId !== "", "action": () => root.sendKeys("", "Delete") },
                { "type": "sep" },
                { "label": "Find", "hint": "⌘F", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "F") }
            ]
            return [
                { "label": "New Window", "hint": "⌘N", "action": () => term ? root.sendKeys("CTRL SHIFT", "N") : root.sendKeys("CTRL", "N") },
                { "label": "New Tab", "hint": "⌘T", "action": () => term ? root.sendKeys("CTRL SHIFT", "T") : root.sendKeys("CTRL", "T") },
                { "label": "Open…", "hint": "⌘O", "enabled": !term, "action": () => root.sendKeys("CTRL", "O") },
                { "type": "sep" },
                { "label": "Close Tab", "hint": "⌘W", "action": () => term ? root.sendKeys("CTRL SHIFT", "W") : root.sendKeys("CTRL", "W") },
                { "label": "Close Window", "hint": "⇧⌘W", "action": () => root.windowDispatch("close", "") },
                { "label": "Save", "hint": "⌘S", "enabled": !term, "action": () => root.sendKeys("CTRL", "S") },
                { "type": "sep" },
                { "label": "Print…", "hint": "⌘P", "enabled": !term, "action": () => root.sendKeys("CTRL", "P") }
            ]
        }

        if (id === "Edit") return [
            { "label": "Undo", "hint": "⌘Z", "enabled": !term, "action": () => root.sendKeys("CTRL", "Z") },
            { "label": "Redo", "hint": "⇧⌘Z", "enabled": !term, "action": () => root.sendKeys("CTRL SHIFT", "Z") },
            { "type": "sep" },
            { "label": "Cut", "hint": "⌘X", "enabled": !term, "action": () => root.sendKeys("CTRL", "X") },
            { "label": "Copy", "hint": "⌘C", "action": () => term ? root.sendKeys("CTRL SHIFT", "C") : root.sendKeys("CTRL", "C") },
            { "label": "Paste", "hint": "⌘V", "action": () => term ? root.sendKeys("CTRL SHIFT", "V") : root.sendKeys("CTRL", "V") },
            { "label": "Select All", "hint": "⌘A", "enabled": !term, "action": () => root.sendKeys("CTRL", "A") },
            { "type": "sep" },
            { "label": "Find", "hint": "⌘F", "enabled": !term, "action": () => root.sendKeys("CTRL", "F") },
            { "type": "sep" },
            { "label": "Emoji & Symbols", "hint": "⌃⌘Space", "action": () => root.run([root.home + "/.local/bin/macos-emoji"]) }
        ]

        if (id === "View") {
            let v = []
            if (finder)
                v = [
                    { "label": "as Icons", "hint": "⌘1", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "1") },
                    { "label": "as List", "hint": "⌘2", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "2") },
                    { "type": "sep" },
                    { "label": "Show Hidden Files", "hint": "⇧⌘.", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "H") },
                    { "type": "sep" }
                ]
            else
                v = [
                    { "label": "Actual Size", "hint": "⌘0", "action": () => term ? root.sendKeys("CTRL SHIFT", "BackSpace") : root.sendKeys("CTRL", "0") },
                    { "label": "Zoom In", "hint": "⌘+", "action": () => term ? root.sendKeys("CTRL SHIFT", "equal") : root.sendKeys("CTRL", "equal") },
                    { "label": "Zoom Out", "hint": "⌘−", "action": () => term ? root.sendKeys("CTRL SHIFT", "minus") : root.sendKeys("CTRL", "minus") },
                    { "type": "sep" }
                ]
            return v.concat([
                { "label": "Enter Full Screen", "hint": "⌃⌘F", "enabled": t.appId !== "",
                  "action": () => root.windowDispatch("fullscreen", 'mode = "fullscreen", action = "toggle"') }
            ])
        }

        if (id === "Go") return [
            { "label": "Back", "hint": "⌘[", "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Left") },
            { "label": "Forward", "hint": "⌘]", "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Right") },
            { "label": "Enclosing Folder", "hint": "⌘↑", "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Up") },
            { "type": "sep" },
            { "label": "Recents", "hint": "⇧⌘F", "action": () => root.openFolder("recent:///") },
            { "label": "Documents", "hint": "⇧⌘O", "action": () => root.openFolder(root.home + "/Documents") },
            { "label": "Desktop", "hint": "⇧⌘D", "action": () => root.openFolder(root.home + "/Desktop") },
            { "label": "Downloads", "hint": "⌥⌘L", "action": () => root.openFolder(root.home + "/Downloads") },
            { "label": "Home", "hint": "⇧⌘H", "action": () => root.openFolder(root.home) },
            { "label": "Network", "hint": "⇧⌘K", "action": () => root.openFolder("network:///") },
            { "type": "sep" },
            { "label": "Go to Folder…", "hint": "⇧⌘G", "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "L") }
        ]

        if (id === "Window") {
            let w = [
                { "label": "Minimize", "hint": "⌘M", "enabled": t.address !== "", "action": () => Minimizer.minimize(t.address) },
                { "label": "Zoom", "enabled": t.address !== "",
                  "action": () => root.windowDispatch("fullscreen", 'mode = "maximized", action = "toggle"') },
                { "label": "Center", "enabled": t.address !== "", "action": () => root.centerWindow() },
                { "type": "sep" },
                { "label": "Bring All to Front", "enabled": t.appId !== "",
                  "action": () => root.appWindows(t.appId).forEach(win => win.activate()) }
            ]
            const wins = t.appId !== "" ? root.appWindows(t.appId) : []
            if (wins.length > 0)
                w.push({ "type": "sep" })
            for (let i = 0; i < wins.length; i++) {
                const win = wins[i]
                w.push({ "label": win.title || name, "checked": win.activated, "action": () => win.activate() })
            }
            return w
        }

        if (id === "Help") return [
            { "label": name + " Help", "enabled": t.appId !== "", "action": () => root.run(["qs", "ipc", "call", "appinfo", "help", t.appId]) },
            { "type": "sep" },
            { "label": "Keyboard Shortcuts", "action": () => root.run([root.home + "/.config/hypr/scripts/keybindings.sh"]) }
        ]

        if (id === "battery") {
            return [
                { "type": "title", "label": "Battery", "detail": Math.round(battery.level * 100) + "%" },
                { "type": "header", "label": "Power Source: " + (battery.charging ? "Power Adapter" : "Battery") },
                { "type": "sep" },
                { "type": "header", "label": "Energy Mode" },
                { "label": "Low Power", "checked": root.powerProfile === "power-saver",
                  "action": () => root.run(["powerprofilesctl", "set", "power-saver"]) },
                { "label": "Automatic", "checked": root.powerProfile === "balanced",
                  "action": () => root.run(["powerprofilesctl", "set", "balanced"]) },
                { "label": "High Power", "checked": root.powerProfile === "performance",
                  "action": () => root.run(["powerprofilesctl", "set", "performance"]) }
            ]
        }

        if (id === "wifi") {
            let m = [
                { "type": "toggle", "label": "Wi-Fi", "get": () => root.wifiEnabled,
                  "set": on => { root.wifiEnabled = on; Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]) } }
            ]
            const nets = root.wifiNetworks
            const current = nets.filter(n => n.active)
            const others = nets.filter(n => !n.active)
            if (current.length > 0) {
                m.push({ "type": "header", "label": "Known Network" })
                m.push({ "label": current[0].ssid, "checked": true, "hint": current[0].secure ? "🔒" : "" })
            }
            if (others.length > 0) {
                m.push({ "type": "header", "label": "Other Networks" })
                for (let i = 0; i < Math.min(others.length, 8); i++) {
                    const ssid = others[i].ssid
                    m.push({ "label": ssid, "hint": others[i].secure ? "🔒" : "",
                             "action": () => root.run(["kitty", "--class", "macos-wifi-connect", "-e",
                                                       "nmcli", "--ask", "device", "wifi", "connect", ssid]) })
                }
            }
            m.push({ "type": "sep" })
            m.push({ "label": "Wi-Fi Settings…", "action": () => root.run(["nm-connection-editor"]) })
            return m
        }

        if (id === "sound") {
            let m = [
                { "type": "title", "label": "Sound" },
                { "type": "slider", "get": () => volume.ready ? volume.sink.audio.volume : 0,
                  "set": v => { if (volume.ready) { volume.sink.audio.muted = false; volume.sink.audio.volume = v } } },
                { "type": "sep" },
                { "type": "header", "label": "Output" }
            ]
            const sinks = Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
            for (let i = 0; i < sinks.length; i++) {
                const node = sinks[i]
                m.push({ "label": node.description || node.nickname || node.name,
                         "checked": node === Pipewire.defaultAudioSink,
                         "action": () => { Pipewire.preferredDefaultAudioSink = node } })
            }
            m.push({ "type": "sep" })
            m.push({ "label": "Sound Settings…", "action": () => root.run(["pavucontrol"]) })
            return m
        }

        return []
    }

    // ==========================================
    // STATUS DATA
    // ==========================================
    property string powerProfile: ""
    Process {
        id: powerProfileProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.powerProfile = this.text.trim()
                if (root.openMenu === "battery")
                    root.menuModel = root.menuEntries("battery")
            }
        }
    }

    property bool wifiEnabled: true
    property var wifiNetworks: []
    Process {
        id: wifiScan
        command: ["bash", "-c", "nmcli -t radio wifi; nmcli -t -f IN-USE,SSID,SECURITY device wifi list --rescan no 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                root.wifiEnabled = lines.length > 0 && lines[0].trim() === "enabled"
                let seen = ({})
                let nets = []
                for (let i = 1; i < lines.length; i++) {
                    // IN-USE:SSID:SECURITY, with ":" inside the SSID escaped as "\:"
                    const parts = lines[i].replace(/\\:/g, "\u0001").split(":")
                    if (parts.length < 3)
                        continue
                    const ssid = parts[1].replace(/\u0001/g, ":")
                    if (ssid === "")
                        continue
                    // The same SSID shows up once per access point; keep one
                    // entry, marked active if any of its access points is.
                    const active = parts[0].trim() === "*"
                    if (seen[ssid]) {
                        seen[ssid].active = seen[ssid].active || active
                        continue
                    }
                    seen[ssid] = { "ssid": ssid, "active": active, "secure": parts[2] !== "" && parts[2] !== "--" }
                    nets.push(seen[ssid])
                }
                root.wifiNetworks = nets
                if (root.openMenu === "wifi")
                    root.menuModel = root.menuEntries("wifi")
            }
        }
    }

    // ==========================================
    // BAR ITEM
    // ==========================================
    // A menu-bar title: text or icon with a rounded highlight while hovered or
    // while its menu is open. Titles with a menuId open that menu on click and,
    // like macOS, take over from another open menu on hover.
    component BarItem: Rectangle {
        id: bi
        property string label: ""
        property string icon: ""
        property int iconSize: 16
        property bool bold: false
        property string menuId: ""
        readonly property bool pressed: bi.menuId !== "" && root.openMenu === bi.menuId
        signal clicked(var mouse)
        signal wheel(var wheel)
        property Component trailing: null

        implicitWidth: Math.max(row.implicitWidth + 16, 26)
        implicitHeight: 24
        radius: 5
        color: bi.pressed ? Qt.rgba(1, 1, 1, 0.22)
             : ma.containsMouse && root.openMenu === "" ? Qt.rgba(1, 1, 1, 0.12)
             : "transparent"

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 5
            Image {
                visible: bi.icon !== ""
                source: bi.icon
                sourceSize.width: bi.iconSize * 2
                sourceSize.height: bi.iconSize * 2
                Layout.preferredWidth: bi.iconSize
                Layout.preferredHeight: bi.iconSize
                fillMode: Image.PreserveAspectFit
            }
            Text {
                visible: bi.label !== ""
                text: bi.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: bi.bold ? Font.Bold : Font.Medium
            }
            Loader { active: bi.trailing !== null; visible: active; sourceComponent: bi.trailing }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (bi.menuId !== "" && mouse.button === Qt.LeftButton)
                    root.toggleMenu(bi.menuId, bi)
                else
                    bi.clicked(mouse)
            }
            onEntered: {
                if (bi.menuId !== "" && root.openMenu !== "" && root.openMenu !== bi.menuId)
                    root.openMenuFor(bi.menuId, bi)
            }
            onWheel: wheel => bi.wheel(wheel)
        }
    }

    // ==========================================
    // LEFT: Apple menu, app name, menus
    // ==========================================
    RowLayout {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        BarItem {
            icon: "icons/apple.svg"
            iconSize: 15
            implicitWidth: 38
            menuId: "apple"
        }

        BarItem { label: root.appName; bold: true; menuId: "app" }

        Repeater {
            model: root.isFinder
                ? ["File", "Edit", "View", "Go", "Window", "Help"]
                : ["File", "Edit", "View", "Window", "Help"]
            BarItem { required property string modelData; label: modelData; menuId: modelData }
        }
    }

    // ==========================================
    // RIGHT: tray, battery, wifi, volume, spotlight, control center, clock
    // ==========================================
    RowLayout {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // System tray. Items in hiddenTrayIds duplicate a built-in status
        // menu: nm-applet keeps running as the Wi-Fi password agent, but the
        // Wi-Fi menu below replaces its icon.
        Repeater {
            model: SystemTray.items
            delegate: BarItem {
                id: trayItem
                required property var modelData
                visible: root.hiddenTrayIds.indexOf(modelData.id) === -1
                icon: modelData.icon
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton && !modelData.onlyMenu)
                        modelData.activate()
                    else if (modelData.hasMenu)
                        trayMenu.open()
                }
                QsMenuAnchor {
                    id: trayMenu
                    menu: trayItem.modelData.menu
                    anchor.item: trayItem
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                }
            }
        }

        // Battery: percentage + drawn battery outline
        BarItem {
            id: battery
            readonly property var device: UPower.displayDevice
            readonly property bool present: device !== null && device.isLaptopBattery && device.isPresent
            readonly property real level: device ? device.percentage : 0
            readonly property bool charging: !UPower.onBattery
            visible: present
            label: MacSettings.get("menubar", "batteryPercent") ? Math.round(level * 100) + "%" : ""
            menuId: "battery"

            // macOS power chime when the charger is plugged in. Armed after
            // startup so UPower settling its initial state stays silent.
            property bool chimeArmed: false
            Timer { interval: 5000; running: true; onTriggered: battery.chimeArmed = true }
            onChargingChanged: {
                if (battery.chimeArmed && battery.charging)
                    Quickshell.execDetached([root.home + "/.local/bin/macos-sound", "power-plug"])
            }

            trailing: Component {
                Item {
                    implicitWidth: 27
                    implicitHeight: 13
                    Rectangle {
                        id: shell
                        width: 24; height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 3.5
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.5)
                        border.width: 1
                        Rectangle {
                            x: 2; y: 2
                            height: parent.height - 4
                            width: Math.max(2, (parent.width - 4) * battery.level)
                            radius: 1.5
                            color: battery.level <= 0.2 && !battery.charging ? "#ff453a" : "#ffffff"
                        }
                        Image {
                            visible: battery.charging
                            anchors.centerIn: parent
                            source: "icons/bolt.svg"
                            sourceSize.width: 14; sourceSize.height: 22
                            width: 7; height: 11
                        }
                    }
                    Rectangle {
                        anchors.left: shell.right
                        anchors.leftMargin: 1
                        anchors.verticalCenter: shell.verticalCenter
                        width: 1.5; height: 4; radius: 1
                        color: Qt.rgba(1, 1, 1, 0.5)
                    }
                }
            }
        }

        // Wi-Fi
        BarItem {
            id: wifi
            property bool connected: false
            icon: connected ? "icons/wifi.svg" : "icons/wifi-off.svg"
            menuId: "wifi"
            Process {
                id: wifiProc
                command: ["bash", "-c", "nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -qE '^wifi:connected$' && echo 1 || echo 0"]
                running: true
                stdout: StdioCollector { onStreamFinished: wifi.connected = this.text.trim() === "1" }
            }
            Timer { interval: 10000; running: true; repeat: true; onTriggered: wifiProc.running = true }
        }

        // Volume: click for the Sound menu, right click mutes, scroll adjusts.
        BarItem {
            id: volume
            readonly property PwNode sink: Pipewire.defaultAudioSink
            readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
            readonly property bool muted: ready ? (sink.audio.muted || sink.audio.volume <= 0) : false
            icon: muted ? "icons/speaker-muted.svg" : "icons/speaker.svg"
            menuId: "sound"
            PwObjectTracker { objects: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && ready)
                    sink.audio.muted = !sink.audio.muted
            }
            onWheel: wheel => {
                if (!ready) return
                sink.audio.muted = false
                sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
            }
        }

        // Spotlight
        BarItem {
            icon: "icons/search.svg"
            iconSize: 15
            onClicked: root.run([root.home + "/.local/bin/macos-spotlight"])
        }

        // Control Center (ControlCenter.qml)
        BarItem {
            icon: "icons/controlcenter.svg"
            onClicked: root.run(["qs", "ipc", "call", "controlcenter", "toggle"])
        }

        // Clock: opens Notification Center
        BarItem {
            SystemClock { id: clock; precision: SystemClock.Minutes }
            label: root.clockText(clock.date)
            onClicked: root.run(["swaync-client", "-t", "-sw"])
        }
    }

    // ==========================================
    // DROPDOWN MENU
    // ==========================================
    HyprlandFocusGrab {
        windows: [menuPopup, root]
        active: root.openMenu !== ""
        onCleared: root.closeMenu()
    }

    PopupWindow {
        id: menuPopup
        visible: root.popupShown
        color: "transparent"
        anchor.window: root
        anchor.rect.x: Math.max(6, Math.min(root.menuX, root.width - menuPopup.implicitWidth - 6))
        anchor.rect.y: root.height + 1
        implicitWidth: Math.max(menuColumn.implicitWidth + 12,
                                root.openMenu === "apple" ? 250 : root.openMenu === "wifi" || root.openMenu === "sound" ? 290 : 200)
        implicitHeight: menuColumn.implicitHeight + 12

        // Checkmark gutter, as in macOS menus that carry checkable items.
        readonly property bool hasChecks: root.menuModel.some(e => e.checked !== undefined)

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(0.16, 0.16, 0.17, 0.82)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.closeMenu()
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 6
                spacing: 0

                Repeater {
                    model: root.menuModel
                    delegate: Loader {
                        id: row
                        required property var modelData
                        readonly property string kind: modelData.type || "item"
                        Layout.fillWidth: true
                        sourceComponent: kind === "sep" ? sepComp
                                       : kind === "title" ? titleComp
                                       : kind === "header" ? headerComp
                                       : kind === "toggle" ? toggleComp
                                       : kind === "slider" ? sliderComp
                                       : itemComp

                        Component {
                            id: sepComp
                            Item {
                                implicitHeight: 11
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                }
                            }
                        }

                        Component {
                            id: titleComp
                            Item {
                                implicitHeight: 26
                                implicitWidth: titleText.implicitWidth + detailText.implicitWidth + 40
                                Text {
                                    id: titleText
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: root.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                Text {
                                    id: detailText
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.detail || ""
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                            }
                        }

                        Component {
                            id: headerComp
                            Item {
                                implicitHeight: 22
                                implicitWidth: headerText.implicitWidth + 20
                                Text {
                                    id: headerText
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: Qt.rgba(1, 1, 1, 0.5)
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Component {
                            id: toggleComp
                            Item {
                                id: toggleRow
                                implicitHeight: 28
                                implicitWidth: toggleText.implicitWidth + 70
                                readonly property bool on: row.modelData.get()
                                Text {
                                    id: toggleText
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: root.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                // macOS switch
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32; height: 18; radius: 9
                                    color: toggleRow.on ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8
                                        y: 1
                                        x: toggleRow.on ? parent.width - width - 1 : 1
                                        color: "#ffffff"
                                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: row.modelData.set(!toggleRow.on)
                                    }
                                }
                            }
                        }

                        Component {
                            id: sliderComp
                            Item {
                                id: sliderRow
                                implicitHeight: 34
                                implicitWidth: 240
                                readonly property real value: row.modelData.get()
                                Rectangle {
                                    id: sliderTrack
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.topMargin: 5
                                    anchors.bottomMargin: 5
                                    radius: height / 2
                                    color: Qt.rgba(1, 1, 1, 0.14)
                                    Rectangle {
                                        width: Math.max(height, sliderTrack.width * Math.min(1, sliderRow.value))
                                        height: parent.height
                                        radius: height / 2
                                        color: "#ffffff"
                                    }
                                    Image {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 14; height: 14
                                        sourceSize.width: 28; sourceSize.height: 28
                                        source: "icons/speaker.svg"
                                        opacity: 0.6
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        function setFrom(mx: real): void {
                                            row.modelData.set(Math.max(0, Math.min(1, mx / width)))
                                        }
                                        onPressed: mouse => setFrom(mouse.x)
                                        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
                                    }
                                }
                            }
                        }

                        Component {
                            id: itemComp
                            Rectangle {
                                id: itemRow
                                readonly property bool enabledItem: row.modelData.enabled !== false
                                    && row.modelData.action !== undefined
                                readonly property bool hot: enabledItem && itemMouse.containsMouse
                                readonly property int gutter: menuPopup.hasChecks ? 22 : 10
                                implicitHeight: 24
                                implicitWidth: gutter + itemLabel.implicitWidth + 36 + itemHint.implicitWidth + 10
                                radius: 5
                                color: hot ? root.accent : "transparent"

                                Text {
                                    visible: row.modelData.checked === true
                                    anchors.left: parent.left
                                    anchors.leftMargin: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "✓"
                                    color: root.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                                Text {
                                    id: itemLabel
                                    anchors.left: parent.left
                                    anchors.leftMargin: itemRow.gutter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: itemRow.enabledItem || row.modelData.checked === true
                                        ? "#ffffff" : Qt.rgba(1, 1, 1, 0.28)
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                                Text {
                                    id: itemHint
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.hint || ""
                                    color: itemRow.hot ? Qt.rgba(1, 1, 1, 0.85)
                                         : itemRow.enabledItem ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.2)
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (!itemRow.enabledItem)
                                            return
                                        const action = row.modelData.action
                                        root.closeMenu()
                                        if (typeof action === "function")
                                            action()
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
