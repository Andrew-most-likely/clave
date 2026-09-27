pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The one place for colors, radii and type sizes of every Quickshell piece.
// Light or dark and the accent color come from System Settings > Appearance
// (appearance.mode, appearance.accent in ~/.config/macos-look/settings.json).
// The rofi, swaync, swayosd and hyprlock styles copy these values by hand.
Singleton {
    id: root

    property string mode: "dark"
    property string accentName: "blue"
    property bool highContrast: false
    property bool reduceTransparency: false
    readonly property bool dark: mode !== "light"

    // --- Type --------------------------------------------------------------
    readonly property string fontFamily: "SF Pro Text"
    readonly property string displayFamily: "SF Pro Display"
    readonly property int fontBody: 13
    readonly property int fontSecondary: 11
    readonly property int fontCaption: 10
    readonly property int fontTitle: 15

    // --- Shape -------------------------------------------------------------
    readonly property int radiusMenu: 10
    readonly property int radiusRow: 5
    readonly property int radiusPanel: 18
    readonly property int radiusCard: 14
    readonly property int radiusControl: 6
    readonly property int menuRowHeight: 24

    // --- Color -------------------------------------------------------------
    // Foreground: text and symbols; fgA(a) for translucent strokes and fills.
    readonly property color fg: dark ? "#ffffff" : "#000000"
    function fgA(a: real): color {
        return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a * 0.85)
    }
    readonly property color secondary: dark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6) : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.6)
    readonly property color tertiary: fgA(0.3)
    readonly property color separator: fgA(highContrast ? 0.35 : 0.12)
    readonly property color border: fgA(highContrast ? 0.45 : 0.14)
    readonly property color control: fgA(0.14)        // buttons, sliders' tracks
    readonly property color controlPressed: fgA(0.24)

    // Surfaces. Translucent ones sit on Hyprland's blur.
    function glass(r: real, g: real, b: real, a: real): color {
        return Qt.rgba(r, g, b, reduceTransparency ? 1 : a)
    }
    readonly property color menu: dark ? glass(0.16, 0.16, 0.17, 0.82) : glass(0.96, 0.96, 0.97, 0.84)
    readonly property color panel: dark ? glass(0.13, 0.13, 0.14, 0.62) : glass(0.93, 0.93, 0.95, 0.66)
    readonly property color card: dark ? glass(0.17, 0.17, 0.18, 0.82) : glass(1, 1, 1, 0.74)
    readonly property color dock: dark ? glass(0.16, 0.16, 0.16, 0.35) : glass(1, 1, 1, 0.38)
    readonly property color tooltip: dark ? glass(0.12, 0.12, 0.13, 0.92) : glass(0.98, 0.98, 0.98, 0.94)
    readonly property color window: dark ? "#1e1e1e" : "#ececec"
    readonly property color sidebar: dark ? glass(0.16, 0.16, 0.17, 0.78) : glass(0.9, 0.9, 0.92, 0.8)
    readonly property color group: dark ? "#2a2a2c" : "#ffffff"          // grouped rows in windows
    readonly property color popup: dark ? "#2f2f31" : "#ffffff"
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.35 : 0.18)

    // macOS system colors, dark and light variants.
    readonly property var accents: ({
        "blue":     ["#0a84ff", "#007aff"], "purple": ["#bf5af2", "#af52de"],
        "pink":     ["#ff375f", "#ff2d55"], "red":    ["#ff453a", "#ff3b30"],
        "orange":   ["#ff9f0a", "#ff9500"], "yellow": ["#ffd60a", "#ffcc00"],
        "green":    ["#30d158", "#34c759"], "graphite": ["#8e8e93", "#8e8e93"]
    })
    readonly property var accentOrder: ["blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"]
    function system(name: string): color {
        const pair = root.accents[name] || root.accents.blue
        return dark ? pair[0] : pair[1]
    }
    readonly property color accent: system(accentName)
    readonly property color onAccent: accentName === "yellow" ? "#000000" : "#ffffff"
    readonly property color red: system("red")
    readonly property color orange: system("orange")
    readonly property color green: system("green")
    readonly property color indigo: dark ? "#5e5ce6" : "#5856d6"
    readonly property color gray: "#8e8e93"

    FileView {
        path: Quickshell.env("HOME") + "/.config/macos-look/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text())
                const a = s.appearance || {}
                const x = s.accessibility || {}
                root.mode = a.mode === "light" ? "light" : "dark"
                root.accentName = root.accents[a.accent] ? a.accent : "blue"
                root.highContrast = x.increaseContrast === true
                root.reduceTransparency = x.reduceTransparency === true
            } catch (e) {
                console.warn("theme: cannot read settings.json:", e)
            }
        }
    }
}
