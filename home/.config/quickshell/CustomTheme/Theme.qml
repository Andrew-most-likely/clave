pragma Singleton
import QtQuick

// macOS (dark) colors shared by the Quickshell pieces.
QtObject {
    readonly property string fontFamily: "SF Pro Text"

    readonly property color menu: "#f02a2a2c"        // menu and popover background
    readonly property color menuBorder: "#33ffffff"
    readonly property color text: "#ffffff"
    readonly property color secondaryText: "#99ffffff"
    readonly property color accent: "#0a84ff"        // System Settings accent blue
    readonly property color textOnAccent: "#ffffff"
}
