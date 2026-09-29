import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import qs.DockApp

// Menu bar: System menu, active app name and its menus, status
// menus (battery, Wi-Fi, sound) and the clock. Replaces the
// StatusbarWindow in shell.qml.
//
// Every title opens a real dropdown. App menus act on the window that was
// focused when the menu opened: they send it the Linux equivalent of the
// shortcut (Hyprland send_shortcut) or run a Hyprland dispatcher. Items with no
// sensible equivalent are shown disabled (greyed out).
PanelWindow {
    id: root

    // shell.qml creates one menu bar per screen; only the primary one owns the IPC target.
    property bool primary: true

    WlrLayershell.namespace: "clave-menubar"
    WlrLayershell.layer: WlrLayer.Top

    anchors { top: true; left: true; right: true }
    implicitHeight: 30
    exclusiveZone: 30
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(1, 1, 1, 0.35)

    readonly property string fontFamily: Theme.fontFamily
    readonly property color fg: Theme.fg
    readonly property color accent: Theme.accent
    readonly property string home: Quickshell.env("HOME")
    readonly property var hiddenTrayIds: ["nm-applet", "blueman"]

    // ==========================================
    // ACTIVE APP
    // ==========================================
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property string activeAppId: activeWindow && activeWindow.appId ? activeWindow.appId : ""
    readonly property bool isFiles: activeAppId === "" || activeAppId === "org.gnome.Nautilus"
    readonly property var terminalIds: ["kitty", "Alacritty", "foot", "org.wezfurlong.wezterm",
        "com.mitchellh.ghostty", "org.gnome.Terminal", "org.gnome.Ptyxis", "org.kde.konsole"]
    readonly property bool isTerminal: terminalIds.indexOf(activeAppId) !== -1
    readonly property string appName: {
        if (root.isFiles)
            return "Files"
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

    // Audio device names without the part they all share: "Raptor Lake-P/U/H
    // cAVS Speaker" and "… HDMI / DisplayPort 1 Output" become "Speaker" and
    // "HDMI / DisplayPort 1 Output".
    function deviceNames(nodes: var): var {
        const names = nodes.map(n => `${n.description || n.nickname || n.name}`)
        if (names.length < 2)
            return names
        let prefix = names[0]
        for (let i = 1; i < names.length; i++)
            while (!names[i].startsWith(prefix))
                prefix = prefix.slice(0, -1)
        const cut = prefix.lastIndexOf(" ") + 1
        return names.map(n => cut > 0 && n.length > cut ? n.slice(cut) : n)
    }

    // The shortcut in ⌃⌥⇧⌘ order, for the keys that are
    // really sent: menu hints show what you can press yourself.
    function keyHint(mods: string, key: string): string {
        const m = mods.split(" ")
        const names = { "comma": ",", "equal": "+", "minus": "−", "BackSpace": "⌫", "Delete": "⌦",
                        "Return": "↩", "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "period": "." }
        return (m.includes("CTRL") ? "⌃" : "") + (m.includes("ALT") ? "⌥" : "")
            + (m.includes("SHIFT") ? "⇧" : "") + (m.includes("SUPER") ? "⌘" : "")
            + (names[key] || key.toUpperCase())
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
        const day = ClaveSettings.get("menubar", "showDay")
        const showDate = ClaveSettings.get("menubar", "showDate")
        let d = ""
        if (day && showDate) d = Qt.formatDateTime(date, "ddd MMM d")
        else if (showDate) d = Qt.formatDateTime(date, "MMM d")
        else if (day) d = Qt.formatDateTime(date, "ddd")
        const time = Qt.formatDateTime(date, ClaveSettings.get("menubar", "clock24h") ? "HH:mm" : "h:mm AP")
        return d === "" ? time : d + "  " + time
    }

    function moveWindow(address: string, workspace: string): void {
        if (address)
            root.hypr(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "address:${address}" })`)
    }

    // Minimized and hidden windows wait on a special workspace; the dock and
    // "Show All" bring them back. Hide moves windows straight there, and
    // without an animation; Window > Minimize goes through Minimizer for
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
    property var menuTarget: ({ "appId": "", "name": "", "address": "", "files": true, "terminal": false })
    property string openMenu: ""
    property var menuModel: []
    property real menuX: 0
    property bool popupShown: false

    function snapshotTarget(): var {
        return {
            "appId": root.activeAppId,
            "name": root.appName,
            "address": root.addressOf(Hyprland.activeToplevel),
            "files": root.isFiles,
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
        // Keyboard shortcuts (hypr/clave/binds.lua): ⌘H, ⌥⌘H, ⌘Q on the
        // focused app. No arguments: the target is always the focused window.
        function hide(): void { if (root.activeAppId !== "") root.hideApp(root.activeAppId) }
        function hideOthers(): void { root.hideOthers(root.activeAppId) }
        function quit(): void { if (root.activeAppId !== "") root.quitApp(root.activeAppId) }
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
        const files = t.files

        if (id === "system") return [
            { "label": "About This Computer", "action": () => root.run(["qs", "ipc", "call", "about", "toggle"]) },
            { "type": "sep" },
            { "label": "System Settings…", "action": () => root.run(["qs", "ipc", "call", "settings", "open", "general"]) },
            { "label": "App Store…", "action": () => root.run(["flatpak", "run", "io.github.kolunmi.Bazaar"]) },
            { "type": "sep" },
            { "label": "Force Quit…", "hint": "⌥⌘⎋", "action": () => root.run(["qs", "ipc", "call", "forcequit", "open"]) },
            { "type": "sep" },
            { "label": "Sleep", "action": () => root.run([root.home + "/.local/bin/clave-power", "-s"]) },
            { "label": "Restart…", "action": () => root.run([root.home + "/.local/bin/clave-power", "-r"]) },
            { "label": "Shut Down…", "action": () => root.run([root.home + "/.local/bin/clave-power", "-p"]) },
            { "type": "sep" },
            { "label": "Lock Screen", "hint": "⌃⌘Q", "action": () => root.run([root.home + "/.local/bin/clave-power", "-l"]) },
            { "label": "Log Out " + root.fullName + "…", "action": () => root.run([root.home + "/.local/bin/clave-power", "-e"]) }
        ]

        if (id === "app") return [
            { "label": "About " + name, "enabled": t.appId !== "", "action": () => root.run(["qs", "ipc", "call", "appinfo", "about", t.appId]) },
            { "type": "sep" },
            { "label": "Settings…", "hint": term ? root.keyHint("CTRL SHIFT", "F2") : root.keyHint("CTRL", "comma"), "enabled": t.appId !== "",
              "action": () => term ? root.sendKeys("CTRL SHIFT", "F2") : root.sendKeys("CTRL", "comma") },
            { "type": "sep" },
            { "label": "Hide " + name, "hint": "⌘H", "enabled": t.appId !== "", "action": () => root.hideApp(t.appId) },
            { "label": "Hide Others", "hint": "⌥⌘H", "action": () => root.hideOthers(t.appId) },
            { "label": "Show All", "action": () => root.showAll() },
            { "type": "sep" },
            { "label": "Quit " + name, "hint": "⌘Q", "enabled": !files, "action": () => root.quitApp(t.appId) }
        ]

        if (id === "File") {
            if (files) return [
                { "label": "New Window", "action": () => root.openFolder(root.home) },
                { "label": "New Folder", "hint": root.keyHint("CTRL SHIFT", "N"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL SHIFT", "N") },
                { "label": "New Tab", "hint": root.keyHint("CTRL", "T"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "T") },
                { "type": "sep" },
                { "label": "Close Window", "hint": "⌘W", "enabled": t.appId !== "", "action": () => root.windowDispatch("close", "") },
                { "type": "sep" },
                { "label": "Get Info", "hint": root.keyHint("ALT", "Return"), "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Return") },
                { "label": "Rename", "enabled": t.appId !== "", "action": () => root.sendKeys("", "F2") },
                { "type": "sep" },
                { "label": "Move to Trash", "hint": root.keyHint("", "Delete"), "enabled": t.appId !== "", "action": () => root.sendKeys("", "Delete") },
                { "type": "sep" },
                { "label": "Find", "hint": root.keyHint("CTRL", "F"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "F") }
            ]
            return [
                { "label": "New Window", "hint": term ? root.keyHint("CTRL SHIFT", "N") : root.keyHint("CTRL", "N"), "action": () => term ? root.sendKeys("CTRL SHIFT", "N") : root.sendKeys("CTRL", "N") },
                { "label": "New Tab", "hint": term ? root.keyHint("CTRL SHIFT", "T") : root.keyHint("CTRL", "T"), "action": () => term ? root.sendKeys("CTRL SHIFT", "T") : root.sendKeys("CTRL", "T") },
                { "label": "Open…", "hint": root.keyHint("CTRL", "O"), "enabled": !term, "action": () => root.sendKeys("CTRL", "O") },
                { "type": "sep" },
                { "label": "Close Tab", "hint": term ? root.keyHint("CTRL SHIFT", "W") : root.keyHint("CTRL", "W"), "action": () => term ? root.sendKeys("CTRL SHIFT", "W") : root.sendKeys("CTRL", "W") },
                { "label": "Close Window", "hint": "⌘W", "action": () => root.windowDispatch("close", "") },
                { "label": "Save", "hint": root.keyHint("CTRL", "S"), "enabled": !term, "action": () => root.sendKeys("CTRL", "S") },
                { "type": "sep" },
                { "label": "Print…", "hint": root.keyHint("CTRL", "P"), "enabled": !term, "action": () => root.sendKeys("CTRL", "P") }
            ]
        }

        if (id === "Edit") return [
            { "label": "Undo", "hint": root.keyHint("CTRL", "Z"), "enabled": !term, "action": () => root.sendKeys("CTRL", "Z") },
            { "label": "Redo", "hint": root.keyHint("CTRL SHIFT", "Z"), "enabled": !term, "action": () => root.sendKeys("CTRL SHIFT", "Z") },
            { "type": "sep" },
            { "label": "Cut", "hint": root.keyHint("CTRL", "X"), "enabled": !term, "action": () => root.sendKeys("CTRL", "X") },
            { "label": "Copy", "hint": term ? root.keyHint("CTRL SHIFT", "C") : root.keyHint("CTRL", "C"), "action": () => term ? root.sendKeys("CTRL SHIFT", "C") : root.sendKeys("CTRL", "C") },
            { "label": "Paste", "hint": term ? root.keyHint("CTRL SHIFT", "V") : root.keyHint("CTRL", "V"), "action": () => term ? root.sendKeys("CTRL SHIFT", "V") : root.sendKeys("CTRL", "V") },
            { "label": "Select All", "hint": root.keyHint("CTRL", "A"), "enabled": !term, "action": () => root.sendKeys("CTRL", "A") },
            { "type": "sep" },
            { "label": "Find", "hint": root.keyHint("CTRL", "F"), "enabled": !term, "action": () => root.sendKeys("CTRL", "F") },
            { "type": "sep" },
            { "label": "Emoji & Symbols", "hint": "⌃⌘Space", "action": () => root.run([root.home + "/.local/bin/clave-emoji"]) }
        ]

        if (id === "View") {
            let v = []
            if (files)
                v = [
                    { "label": "as Icons", "hint": root.keyHint("CTRL", "1"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "1") },
                    { "label": "as List", "hint": root.keyHint("CTRL", "2"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "2") },
                    { "type": "sep" },
                    { "label": "Show Hidden Files", "hint": root.keyHint("CTRL", "H"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "H") },
                    { "type": "sep" }
                ]
            else
                v = [
                    { "label": "Actual Size", "hint": term ? root.keyHint("CTRL SHIFT", "BackSpace") : root.keyHint("CTRL", "0"), "action": () => term ? root.sendKeys("CTRL SHIFT", "BackSpace") : root.sendKeys("CTRL", "0") },
                    { "label": "Zoom In", "hint": term ? root.keyHint("CTRL SHIFT", "equal") : root.keyHint("CTRL", "equal"), "action": () => term ? root.sendKeys("CTRL SHIFT", "equal") : root.sendKeys("CTRL", "equal") },
                    { "label": "Zoom Out", "hint": term ? root.keyHint("CTRL SHIFT", "minus") : root.keyHint("CTRL", "minus"), "action": () => term ? root.sendKeys("CTRL SHIFT", "minus") : root.sendKeys("CTRL", "minus") },
                    { "type": "sep" }
                ]
            return v.concat([
                { "label": "Enter Full Screen", "hint": "⌃⌘F", "enabled": t.appId !== "",
                  "action": () => root.windowDispatch("fullscreen", 'mode = "fullscreen", action = "toggle"') }
            ])
        }

        if (id === "Go") return [
            { "label": "Back", "hint": root.keyHint("ALT", "Left"), "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Left") },
            { "label": "Forward", "hint": root.keyHint("ALT", "Right"), "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Right") },
            { "label": "Enclosing Folder", "hint": root.keyHint("ALT", "Up"), "enabled": t.appId !== "", "action": () => root.sendKeys("ALT", "Up") },
            { "type": "sep" },
            { "label": "Recents", "action": () => root.openFolder("recent:///") },
            { "label": "Documents", "action": () => root.openFolder(root.home + "/Documents") },
            { "label": "Desktop", "action": () => root.openFolder(root.home + "/Desktop") },
            { "label": "Downloads", "action": () => root.openFolder(root.home + "/Downloads") },
            { "label": "Home", "action": () => root.openFolder(root.home) },
            { "label": "Network", "action": () => root.openFolder("network:///") },
            { "type": "sep" },
            { "label": "Go to Folder…", "hint": root.keyHint("CTRL", "L"), "enabled": t.appId !== "", "action": () => root.sendKeys("CTRL", "L") }
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
            { "label": "Keyboard Shortcuts", "hint": "⌘/", "action": () => root.run([root.home + "/.local/bin/clave-keybinds"]) }
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
            let m = []
            m.push({ "type": "title", "label": "Ethernet",
                     "detail": root.ethConnected ? "Connected" : root.ethPresent ? "Not Connected" : "No Adapter" })
            if (root.ethConnected && root.ethName !== "")
                m.push({ "label": root.ethName, "checked": true })
            m.push({ "type": "sep" })
            m.push({ "type": "toggle", "label": "Wi-Fi", "get": () => root.wifiEnabled,
                  "set": on => { root.wifiEnabled = on; Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]) } })
            const nets = root.wifiNetworks
            const current = nets.filter(n => n.active)
            const others = nets.filter(n => !n.active)
            if (current.length > 0) {
                m.push({ "type": "header", "label": "Known Network" })
                m.push({ "label": current[0].ssid, "checked": true, "hint": root.wifiHint(current[0]) })
            }
            if (others.length > 0) {
                m.push({ "type": "header", "label": "Other Networks" })
                for (let i = 0; i < Math.min(others.length, 8); i++) {
                    const ssid = others[i].ssid
                    // NetworkManager asks for the password through its own
                    // agent (nm-applet), which keeps it in the keyring: this
                    // shell never sees it.
                    m.push({ "label": ssid, "hint": root.wifiHint(others[i]),
                             "action": () => root.run(["nmcli", "device", "wifi", "connect", ssid]) })
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
            const sinkNames = root.deviceNames(sinks)
            for (let i = 0; i < sinks.length; i++) {
                const node = sinks[i]
                m.push({ "label": sinkNames[i],
                         "checked": node === Pipewire.defaultAudioSink,
                         "action": () => { Pipewire.preferredDefaultAudioSink = node } })
            }
            const sources = Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio
                                                         && !`${n.name}`.endsWith(".monitor"))
            if (sources.length > 0) {
                m.push({ "type": "sep" })
                m.push({ "type": "header", "label": "Input" })
                const sourceNames = root.deviceNames(sources)
                for (let i = 0; i < sources.length; i++) {
                    const node = sources[i]
                    m.push({ "label": sourceNames[i],
                             "checked": node === Pipewire.defaultAudioSource,
                             "action": () => { Pipewire.preferredDefaultAudioSource = node } })
                }
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
    // Wired network: shown in the menu bar in place of Wi-Fi while connected
    // (NetworkManager routes through it first).
    property bool ethConnected: false
    // A wired adapter exists (built-in port, dock or USB), cable or not.
    property bool ethPresent: false
    property string ethName: ""
    // Full name from the account (GECOS), for "Log Out <name>…".
    property string fullName: Quickshell.env("USER")
    Process {
        running: true
        command: ["getent", "passwd", Quickshell.env("USER")]
        stdout: StdioCollector {
            onStreamFinished: {
                const gecos = (this.text.split(":")[4] || "").split(",")[0].trim()
                if (gecos !== "")
                    root.fullName = gecos
            }
        }
    }

    property var wifiNetworks: []
    // Lock for secured networks, then signal bars (strongest shown first).
    function wifiHint(n: var): string {
        const bars = n.signal >= 67 ? "▂▄▆" : n.signal >= 34 ? "▂▄" : "▂"
        return (n.secure ? "🔒 " : "") + bars
    }
    Process {
        id: wifiScan
        command: ["bash", "-c", "nmcli -t radio wifi; nmcli -t -f IN-USE,SSID,SECURITY,SIGNAL device wifi list --rescan no 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                root.wifiEnabled = lines.length > 0 && lines[0].trim() === "enabled"
                let seen = ({})
                let nets = []
                for (let i = 1; i < lines.length; i++) {
                    // IN-USE:SSID:SECURITY:SIGNAL, with ":" inside the SSID escaped as "\:"
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
                    seen[ssid] = { "ssid": ssid, "active": active, "secure": parts[2] !== "" && parts[2] !== "--",
                                   "signal": parseInt(parts[3]) || 0 }
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
    // take over from another open menu on hover.
    component BarItem: Rectangle {
        id: bi
        property string label: ""
        property string icon: ""
        property int iconSize: 16
        property bool bold: false
        property bool dim: false
        property string menuId: ""
        readonly property bool pressed: bi.menuId !== "" && root.openMenu === bi.menuId
        signal clicked(var mouse)
        signal wheel(var wheel)
        property Component trailing: null

        implicitWidth: Math.max(row.implicitWidth + 16, 26)
        implicitHeight: 24
        radius: Theme.radiusRow
        color: bi.pressed ? Theme.fgA(0.22)
             : ma.containsMouse && root.openMenu === "" ? Theme.fgA(0.12)
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
                textFormat: Text.PlainText
                visible: bi.label !== ""
                text: bi.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: bi.bold ? Font.Bold : Font.Medium
                opacity: bi.dim ? 0.5 : 1
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
    // LEFT: System menu, app name, menus
    // ==========================================
    RowLayout {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        BarItem {
            icon: ClaveSettings.logo
            iconSize: 15
            implicitWidth: 38
            menuId: "system"
        }

        BarItem { label: root.appName; bold: true; menuId: "app" }

        Repeater {
            model: root.isFiles
                ? ["File", "Edit", "View", "Go", "Window", "Help"]
                : ["File", "Edit", "View", "Window", "Help"]
            BarItem { required property string modelData; label: modelData; menuId: modelData }
        }

        // Space numbers for this screen (FEAT-1), like stock Hyprland bars
        // show them. Off by default; while off, nothing is created. Hyprland's
        // own events keep the list current, so there is no polling.
        Loader {
            active: ClaveSettings.get("menubar", "spaceNumbers")
            visible: active
            Layout.leftMargin: 8
            sourceComponent: RowLayout {
                id: spaces
                readonly property var monitor: Hyprland.monitorFor(root.screen)
                spacing: 0
                Repeater {
                    model: Hyprland.workspaces
                    BarItem {
                        required property var modelData
                        visible: modelData.id > 0 && modelData.monitor === spaces.monitor
                        label: modelData.name
                        implicitWidth: 24
                        bold: modelData === spaces.monitor?.activeWorkspace
                        dim: !bold
                        onClicked: root.hypr(`hl.dsp.focus({ workspace = ${modelData.id} })`)
                    }
                }
            }
        }
    }

    // ==========================================
    // RIGHT: tray, battery, wifi, volume, search, control center, clock
    // ==========================================
    RowLayout {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // Stop button while a screen recording runs (SHELL-1).
        BarItem {
            visible: Recorder.recording
            icon: Qt.resolvedUrl("icons/record-stop.svg")
            onClicked: Recorder.stop()
        }

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
            label: ClaveSettings.get("menubar", "batteryPercent") ? Math.round(level * 100) + "%" : ""
            menuId: "battery"

            // Power chime when the charger is plugged in. Armed after
            // startup so UPower settling its initial state stays silent.
            property bool chimeArmed: false
            Timer { interval: 5000; running: true; onTriggered: battery.chimeArmed = true }
            onChargingChanged: {
                if (battery.chimeArmed && battery.charging)
                    Quickshell.execDetached([root.home + "/.local/bin/clave-sound", "power-plug"])
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
                        border.color: Theme.fgA(0.5)
                        border.width: 1
                        Rectangle {
                            x: 2; y: 2
                            height: parent.height - 4
                            width: Math.max(2, (parent.width - 4) * battery.level)
                            radius: 1.5
                            color: battery.level <= 0.2 && !battery.charging ? "#ff453a" : Theme.fg
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
                        color: Theme.fgA(0.5)
                    }
                }
            }
        }

        // Network: Ethernet while a cable is connected, otherwise Wi-Fi.
        BarItem {
            id: wifi
            property bool connected: false
            icon: root.ethConnected ? "icons/ethernet.svg" : connected ? "icons/wifi.svg" : "icons/wifi-off.svg"
            menuId: "wifi"
            Process {
                id: wifiProc
                // Prints "WIFI ETH NAME": WIFI is 1 or 0; ETH is 2 connected, 1 adapter
                // without a connection, 0 no adapter; then the wired connection's name.
                command: ["bash", "-c", "nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '"
                    + "$1 == \"wifi\" && $2 == \"connected\" { w = 1 } "
                    + "$1 == \"ethernet\" && $2 != \"unmanaged\" && !e { e = 1 } "
                    + "$1 == \"ethernet\" && $2 == \"connected\" && e < 2 { e = 2; sub(/^[^:]*:[^:]*:/, \"\"); n = $0 } "
                    + "END { print w + 0, e + 0, n }'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = this.text.trim()
                        const parts = t.split(" ")
                        wifi.connected = parts[0] === "1"
                        root.ethConnected = parts[1] === "2"
                        root.ethPresent = parts[1] !== "0"
                        root.ethName = root.ethConnected ? t.split(" ").slice(2).join(" ").replace(/\\:/g, ":") : ""
                    }
                }
            }
            // NetworkManager reports each change; check again then, not on a timer.
            Process {
                running: true
                command: ["nmcli", "monitor"]
                stdout: SplitParser { onRead: wifiProc.running = true }
            }
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

        // Search
        BarItem {
            icon: "icons/search.svg"
            iconSize: 15
            onClicked: root.run([root.home + "/.local/bin/clave-search"])
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
                                root.openMenu === "system" ? 250 : root.openMenu === "wifi" || root.openMenu === "sound" ? 290 : 200)
        implicitHeight: menuColumn.implicitHeight + 12

        // Checkmark gutter, for menus that carry checkable items.
        readonly property bool hasChecks: root.menuModel.some(e => e.checked !== undefined)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMenu
            color: Theme.menu
            border.color: Theme.border
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
                                    color: Theme.fgA(0.12)
                                }
                            }
                        }

                        Component {
                            id: titleComp
                            Item {
                                implicitHeight: 26
                                implicitWidth: titleText.implicitWidth + detailText.implicitWidth + 40
                                Text {
                                    textFormat: Text.PlainText
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
                                    textFormat: Text.PlainText
                                    id: detailText
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.detail || ""
                                    color: Theme.fgA(0.55)
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
                                    textFormat: Text.PlainText
                                    id: headerText
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: Theme.fgA(0.5)
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
                                    textFormat: Text.PlainText
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
                                // Switch
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32; height: 18; radius: 9
                                    color: toggleRow.on ? root.accent : Theme.fgA(0.2)
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
                                    color: Theme.fgA(0.14)
                                    Rectangle {
                                        width: Math.max(height, sliderTrack.width * Math.min(1, sliderRow.value))
                                        height: parent.height
                                        radius: height / 2
                                        color: Theme.fg
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
                                radius: Theme.radiusRow
                                color: hot ? root.accent : "transparent"

                                Text {
                                    textFormat: Text.PlainText
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
                                    textFormat: Text.PlainText
                                    id: itemLabel
                                    anchors.left: parent.left
                                    anchors.leftMargin: itemRow.gutter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    color: itemRow.hot ? Theme.onAccent
                                         : itemRow.enabledItem || row.modelData.checked === true ? Theme.fg : Theme.fgA(0.28)
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    id: itemHint
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (row.modelData.hint || "").replace(/⌘/g, ClaveSettings.superKey)
                                    color: itemRow.hot ? Qt.alpha(Theme.onAccent, 0.85)
                                         : itemRow.enabledItem ? Theme.fgA(0.45) : Theme.fgA(0.2)
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
