pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Settings for the Clave shell, edited in System Settings (SettingsWindow).
//
//   ~/.config/clave/settings.json  read here and by the Quickshell parts
//   ~/.config/clave/hypr.lua       generated for hypr/clave/*.lua (trackpad,
//                                       mouse, keyboard, traffic lights,
//                                       accessibility); applied with a reload
//
// Every feature that could matter for privacy or security has a switch here
// ("privacy", "features"), and the code that runs the feature
// checks it. Anything that reaches the network is off by default.
//
// Values missing from the file fall back to the defaults below.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/clave"
    // 24-hour clock where the locale uses one (no AM/PM in its time format).
    readonly property bool locale24h: !/a|AP/i.test(Qt.locale().timeFormat(Locale.ShortFormat))

    readonly property var defaults: ({
        "menubar":    { "batteryPercent": true, "clock24h": root.locale24h, "showDate": true, "showDay": true,
                        "spaceNumbers": false },
        "hotCorners": { "topLeft": "none", "topRight": "none",
                        "bottomLeft": "none", "bottomRight": "none" },
        "windows":    { "minimizeEffect": "genie", "trafficLights": true, "noBarApps": [] },
        "trackpad":   { "tapToClick": true, "naturalScroll": true },
        "mouse":      { "speed": 0, "acceleration": true, "naturalScroll": false, "leftHanded": false },
        "keyboard":   { "repeatRate": 25, "repeatDelay": 600, "layout": "us", "capsLock": "",
                        "superGlyph": "command", "superEditing": false },
        "sound":      { "uiSounds": true },
        "appearance": { "mode": "dark", "accent": "blue" },
        "display":    { "nightLightTemp": 4500 },
        // "wallpaper" (blurred) or "picture" (clave-prefs lockscreen).
        "lockScreen": { "background": "wallpaper" },
        "screenshots": { "folder": "", "saveTo": "pictures", "timer": 0, "thumbnail": true, "pointer": false },
        // Clipboard history lives in memory ($XDG_RUNTIME_DIR) unless kept.
        "privacy":    { "clipboardHistory": true, "clipboardKeep": false, "clipboardImages": false,
                        "albumArtOnline": false, "wallpaperApps": "ask", "capturePrompt": true },
        "features":   { "appSwitcher": true, "windowTiling": true, "screenRecording": true },
        "accessibility": { "reduceMotion": false, "reduceTransparency": false, "increaseContrast": false },
        // App id -> local PNG or SVG shown instead of the app's icon (APP-4).
        // clave-prefs icon set|reset writes it.
        "icons":      {}
    })

    property var data: JSON.parse(JSON.stringify(defaults))

    // Hot corner choices, in the order System Settings lists them.
    readonly property var cornerActions: [
        { "id": "none",           "label": "—",                    "cmd": [] },
        { "id": "overview",       "label": "Overview",             "cmd": ["qs", "ipc", "call", "overview", "toggle"] },
        { "id": "notifications",  "label": "Notification Center",  "cmd": ["swaync-client", "-t", "-sw"] },
        { "id": "apps",           "label": "Apps",                 "cmd": [home + "/.local/bin/clave-apps"] },
        { "id": "search",         "label": "Search",               "cmd": [home + "/.local/bin/clave-search"] },
        { "id": "controlcenter",  "label": "Control Center",       "cmd": ["qs", "ipc", "call", "controlcenter", "toggle"] },
        // Locks first, so a sleeping display never hides an unlocked session.
        { "id": "displaysleep",   "label": "Put Display to Sleep", "cmd": [home + "/.local/bin/clave-power", "-d"] },
        { "id": "lock",           "label": "Lock Screen",          "cmd": [home + "/.local/bin/clave-power", "-l"] }
    ]

    function get(group: string, key: string): var {
        const g = root.data[group]
        if (g !== undefined && g[key] !== undefined)
            return g[key]
        return root.defaults[group][key]
    }

    // The glyph for the Super key in menus and the shortcut list (FEAT-7):
    // ⌘, or ❖ for keyboards labeled with another symbol.
    readonly property string superKey: get("keyboard", "superGlyph") === "super" ? "❖" : "⌘"

    function cornerCommand(corner: string): var {
        const id = root.get("hotCorners", corner)
        for (let i = 0; i < root.cornerActions.length; i++)
            if (root.cornerActions[i].id === id)
                return root.cornerActions[i].cmd
        return []
    }

    function set(group: string, key: string, value: var): void {
        let d = JSON.parse(JSON.stringify(root.data))
        if (d[group] === undefined)
            d[group] = {}
        d[group][key] = value
        root.data = d
        settingsFile.setText(JSON.stringify(d, null, 4) + "\n")
        if (["trackpad", "mouse", "keyboard", "windows", "accessibility"].includes(group)
                || (group === "privacy" && key === "capturePrompt"))
            root.writeHypr()
        if (group === "sound")
            root.writeSoundFlag()
        if (group === "privacy" && key.startsWith("clipboard"))
            Quickshell.execDetached([root.home + "/.local/bin/clave-clipboard", "restart"])
    }

    // Light or dark for the whole desktop: the shell (Theme reads the setting)
    // and GTK/Qt apps (clave-prefs).
    function setAppearance(mode: string): void {
        if (mode !== "light" && mode !== "dark")
            return
        root.set("appearance", "mode", mode)
        Quickshell.execDetached([root.home + "/.local/bin/clave-prefs", "appearance", "mode", mode])
    }

    function setAccent(name: string): void {
        root.set("appearance", "accent", name)
        Quickshell.execDetached([root.home + "/.local/bin/clave-prefs", "appearance", "accent", name])
    }

    // Defaults merged with the file, key by key. Groups the defaults do not
    // know are kept too: helper scripts read settings of their own from it.
    function apply(text: string): void {
        let merged = JSON.parse(JSON.stringify(root.defaults))
        try {
            const parsed = JSON.parse(text)
            for (let g in parsed) {
                if (typeof parsed[g] !== "object" || parsed[g] === null || Array.isArray(parsed[g]))
                    continue
                if (merged[g] === undefined)
                    merged[g] = {}
                for (let k in parsed[g])
                    merged[g][k] = parsed[g][k]
            }
        } catch (e) {
            console.warn("clave settings: cannot parse settings.json:", e)
        }
        root.data = merged
    }

    // Window classes that get no traffic lights because they draw their own
    // (ISSUE-1). Only plain class names reach the Hyprland config.
    function noBarApps(): var {
        const list = root.get("windows", "noBarApps")
        return Array.isArray(list) ? list.filter(c => /^[A-Za-z0-9._-]+$/.test(c)) : []
    }

    function writeHypr(): void {
        const b = v => v ? "true" : "false"
        hyprFile.setText("-- Generated by System Settings (Quickshell Clave/ClaveSettings.qml).\n"
            + "-- Read by hypr/clave/*.lua. Edit in System Settings instead.\n"
            + "return {\n"
            + "    tap_to_click   = " + b(root.get("trackpad", "tapToClick")) + ",\n"
            + "    natural_scroll = " + b(root.get("trackpad", "naturalScroll")) + ",\n"
            + "    traffic_lights = " + b(root.get("windows", "trafficLights")) + ",\n"
            + "    mouse_speed    = " + Number(root.get("mouse", "speed")) + ",\n"
            + "    mouse_accel    = " + b(root.get("mouse", "acceleration")) + ",\n"
            + "    mouse_natural  = " + b(root.get("mouse", "naturalScroll")) + ",\n"
            + "    left_handed    = " + b(root.get("mouse", "leftHanded")) + ",\n"
            + "    repeat_rate    = " + Math.round(root.get("keyboard", "repeatRate")) + ",\n"
            + "    repeat_delay   = " + Math.round(root.get("keyboard", "repeatDelay")) + ",\n"
            + "    kb_layout      = " + JSON.stringify(`${root.get("keyboard", "layout")}`) + ",\n"
            + "    caps_lock      = " + JSON.stringify(`${root.get("keyboard", "capsLock")}`) + ",\n"
            + "    reduce_motion  = " + b(root.get("accessibility", "reduceMotion")) + ",\n"
            + "    reduce_transparency = " + b(root.get("accessibility", "reduceTransparency")) + ",\n"
            + "    increase_contrast   = " + b(root.get("accessibility", "increaseContrast")) + ",\n"
            + "    enforce_permissions = " + b(root.get("privacy", "capturePrompt")) + ",\n"
            + "    super_editing  = " + b(root.get("keyboard", "superEditing")) + ",\n"
            + "    no_bar_apps    = { " + root.noBarApps().map(c => JSON.stringify(c)).join(", ") + " },\n"
            + "}\n")
    }

    // ~/.local/bin/clave-sound stays silent while this file exists.
    function writeSoundFlag(): void {
        Quickshell.execDetached(["sh", "-c", root.get("sound", "uiSounds")
            ? "rm -f \"$HOME/.config/clave/mute-ui-sounds\""
            : "touch \"$HOME/.config/clave/mute-ui-sounds\""])
    }

    FileView {
        id: settingsFile
        path: root.dir + "/settings.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    FileView {
        id: hyprFile
        path: root.dir + "/hypr.lua"
        printErrors: false
    }

    // The logo in the menu bar and About window (FEAT-6). A file the user puts
    // at ~/.config/clave/branding/logo.svg replaces the keystone. Read once at
    // start; no watcher.
    property bool userLogo: false
    readonly property string logo: userLogo
        ? "file://" + dir + "/branding/logo.svg"
        : Qt.resolvedUrl("icons/logo.svg")

    FileView {
        path: root.dir + "/branding/logo.svg"
        printErrors: false
        onLoaded: root.userLogo = true
    }
}
