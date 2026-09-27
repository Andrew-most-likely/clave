pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Settings for the macOS pieces, edited in System Settings (SettingsWindow).
//
//   ~/.config/macos-look/settings.json  read here and by the Quickshell parts
//   ~/.config/macos-look/hypr.lua       generated for hypr/macos/*.lua (trackpad,
//                                       mouse, keyboard, traffic lights,
//                                       accessibility); applied with a reload
//
// Every feature that could matter for privacy or security has a switch here
// ("privacy", "features", "spotlight"), and the code that runs the feature
// checks it. Anything that reaches the network is off by default.
//
// Values missing from the file fall back to the defaults below.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/macos-look"
    // 24-hour clock where the locale uses one (no AM/PM in its time format).
    readonly property bool locale24h: !/a|AP/i.test(Qt.locale().timeFormat(Locale.ShortFormat))

    readonly property var defaults: ({
        "menubar":    { "batteryPercent": true, "clock24h": root.locale24h, "showDate": true, "showDay": true },
        "hotCorners": { "topLeft": "none", "topRight": "none",
                        "bottomLeft": "none", "bottomRight": "none" },
        "windows":    { "minimizeEffect": "genie", "trafficLights": true },
        "trackpad":   { "tapToClick": true, "naturalScroll": true },
        "mouse":      { "speed": 0, "acceleration": true, "naturalScroll": false, "leftHanded": false },
        "keyboard":   { "repeatRate": 25, "repeatDelay": 600, "layout": "us", "capsLock": "" },
        "sound":      { "uiSounds": true },
        "appearance": { "accent": "blue" },
        "display":    { "nightShiftTemp": 4500 },
        "screenshots": { "folder": "", "saveTo": "pictures", "timer": 0, "thumbnail": true, "pointer": false },
        // Clipboard history lives in memory ($XDG_RUNTIME_DIR) unless kept.
        "privacy":    { "clipboardHistory": true, "clipboardKeep": false, "clipboardImages": false,
                        "albumArtOnline": false, "wallpaperApps": "ask", "capturePrompt": true },
        "features":   { "appSwitcher": true, "windowTiling": true, "screenRecording": true },
        "spotlight":  { "apps": true, "settings": true, "calculator": true, "conversions": true,
                        "files": true, "web": false, "hideUtilities": true },
        "accessibility": { "reduceMotion": false, "reduceTransparency": false, "increaseContrast": false }
    })

    property var data: JSON.parse(JSON.stringify(defaults))

    // Hot corner choices, in the order System Settings lists them.
    readonly property var cornerActions: [
        { "id": "none",           "label": "—",                    "cmd": [] },
        { "id": "missioncontrol", "label": "Mission Control",      "cmd": ["qs", "ipc", "call", "missioncontrol", "toggle"] },
        { "id": "notifications",  "label": "Notification Center",  "cmd": ["swaync-client", "-t", "-sw"] },
        { "id": "launchpad",      "label": "Launchpad",            "cmd": [home + "/.local/bin/macos-launchpad"] },
        { "id": "spotlight",      "label": "Spotlight",            "cmd": [home + "/.local/bin/macos-spotlight"] },
        { "id": "controlcenter",  "label": "Control Center",       "cmd": ["qs", "ipc", "call", "controlcenter", "toggle"] },
        // Locks first, so a sleeping display never hides an unlocked session.
        { "id": "displaysleep",   "label": "Put Display to Sleep", "cmd": [home + "/.local/bin/macos-power", "-d"] },
        { "id": "lock",           "label": "Lock Screen",          "cmd": [home + "/.local/bin/macos-power", "-l"] }
    ]

    function get(group: string, key: string): var {
        const g = root.data[group]
        if (g !== undefined && g[key] !== undefined)
            return g[key]
        return root.defaults[group][key]
    }

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
            Quickshell.execDetached([root.home + "/.local/bin/macos-clipboard", "restart"])
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
            console.warn("macos settings: cannot parse settings.json:", e)
        }
        root.data = merged
    }

    function writeHypr(): void {
        const b = v => v ? "true" : "false"
        hyprFile.setText("-- Generated by System Settings (Quickshell MacOS/MacSettings.qml).\n"
            + "-- Read by hypr/macos/*.lua. Edit in System Settings instead.\n"
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
            + "}\n")
    }

    // ~/.local/bin/macos-sound stays silent while this file exists.
    function writeSoundFlag(): void {
        Quickshell.execDetached(["sh", "-c", root.get("sound", "uiSounds")
            ? "rm -f \"$HOME/.config/macos-look/mute-ui-sounds\""
            : "touch \"$HOME/.config/macos-look/mute-ui-sounds\""])
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
}
