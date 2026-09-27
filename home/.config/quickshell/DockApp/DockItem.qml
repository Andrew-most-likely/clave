import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.CustomTheme
import qs.DockApp

// One app in the dock: its icon, a running/focused indicator, a tooltip with
// the app name and a right-click menu to pin or unpin it.
Item {
    id: item

    // { key, appId, desktopEntry, name, iconSource, windows, pinned } — built by
    // DockWindow, which owns the desktop-entry lookup.
    property var entry: null
    property int iconSize: 32
    // The dock window. It owns the (single) context menu, which is drawn inside
    // its own surface — see DockMenu for why it is not a popup window.
    property var dockWindow: null

    // Whether the open context menu belongs to this item.
    readonly property bool menuOpen: item.dockWindow
        && item.dockWindow.menuItem === item

    signal pinRequested(string key)
    signal unpinRequested(string key)

    readonly property var windows: item.entry ? item.entry.windows : []
    readonly property bool running: item.windows.length > 0
    readonly property bool pinned: item.entry ? item.entry.pinned : false
    readonly property var desktopEntry: item.entry ? item.entry.desktopEntry : null
    readonly property string appName: item.entry ? item.entry.name : ""
    readonly property string iconSource: item.entry ? item.entry.iconSource : ""

    // Whether one of this app's windows is the focused one.
    readonly property bool active: {
        const focused = ToplevelManager.activeToplevel
        if (!focused)
            return false
        for (let i = 0; i < item.windows.length; i++)
            if (item.windows[i] === focused)
                return true
        return false
    }

    readonly property bool highlighted: itemMouse.containsMouse || item.menuOpen

    // Hover magnification, computed by the dock from this item's resting
    // position (see DockWindow.magnifyFor). The icon grows up out of the pill
    // and the item widens so its neighbours make room.
    property real baseCenter: 0
    readonly property real liveCenter: item.dockWindow ? item.dockWindow.centerOf(item) : 0
    onLiveCenterChanged: if (item.dockWindow && !item.dockWindow.magnifying) baseCenter = liveCenter
    Component.onCompleted: baseCenter = liveCenter
    property real magnification: item.dockWindow ? item.dockWindow.magnifyFor(item.baseCenter) : 1
    Behavior on magnification {
        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
    }
    onMagnificationChanged: if (tooltip.visible) tooltip.anchor.updateAnchor()

    implicitWidth: item.iconSize * item.magnification + 16
    implicitHeight: item.iconSize + 18

    // --- ACTIONS ---
    // Only installed desktop entries are launched. A window's app id is chosen
    // by the app itself (sandboxed ones included), so it is never run as a
    // command: apps without an entry can be focused but not launched or pinned.
    function launch(): void {
        if (item.desktopEntry)
            item.desktopEntry.execute()
    }

    // Brings back this app's windows that were minimized or hidden (they wait
    // on special:minimized) onto the current workspace and focuses the last
    // one. Minimized windows pour back out of the icon (see Minimizer).
    // Returns whether there was anything to restore.
    function restoreMinimized(): bool {
        const current = Hyprland.focusedWorkspace
        if (!current)
            return false
        let found = []
        const list = Hyprland.toplevels.values
        for (let i = 0; i < list.length; i++) {
            const t = list[i]
            if (Minimizer.isMinimized(t) && item.windows.indexOf(t.wayland) !== -1)
                found.push(Minimizer.normalize(`${t.address}`))
        }
        for (let i = 0; i < found.length; i++)
            Minimizer.restore(found[i], `${current.id}`, i === found.length - 1)
        return found.length > 0
    }

    // Focus the app: its only window, or — when it has several — the one after
    // the currently focused one, so repeated clicks cycle through them.
    // Minimized windows come back first, as on macOS.
    function activate(): void {
        if (!item.running) {
            item.launch()
            return
        }
        if (item.restoreMinimized())
            return
        if (item.windows.length === 1) {
            item.windows[0].activate()
            return
        }
        let index = -1
        const focused = ToplevelManager.activeToplevel
        for (let i = 0; i < item.windows.length; i++)
            if (item.windows[i] === focused)
                index = i
        item.windows[(index + 1) % item.windows.length].activate()
    }

    function closeWindows(): void {
        // Copy first: closing mutates the toplevel list this array comes from.
        const list = item.windows.slice()
        for (let i = 0; i < list.length; i++)
            list[i].close()
    }

    // Entries for the right-click menu, rebuilt each time it opens.
    function menuActions(): var {
        let actions = []
        if (item.pinned)
            actions.push({ "label": "Unpin from Dock",
                           "callback": () => item.unpinRequested(item.entry.key) })
        else if (item.desktopEntry)
            actions.push({ "label": "Pin to Dock",
                           "callback": () => item.pinRequested(item.entry.key) })
        if (item.desktopEntry)
            actions.push({ "label": item.running ? "New Window" : "Launch",
                           "callback": () => item.launch() })
        if (item.running)
            actions.push({ "label": item.windows.length > 1
                               ? "Close All Windows" : "Close Window",
                           "callback": () => item.closeWindows() })
        return actions
    }

    // The icon image, which the genie animation pours windows into.
    readonly property Item iconItem: iconImage

    // --- ICON ---
    Image {
        id: iconImage
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        source: item.iconSource
        width: item.iconSize * item.magnification
        height: width
        sourceSize.width: item.iconSize * 3
        sourceSize.height: item.iconSize * 3
        fillMode: Image.PreserveAspectFit
        // The icon darkens while pressed.
        opacity: itemMouse.pressed ? 0.6 : 1

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
    }

    // --- RUNNING INDICATOR ---
    // A dot below the icon for a running app; it widens into a short bar while
    // one of its windows has focus.
    Rectangle {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        height: 4
        width: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.8)
        opacity: item.running && DockSettings.settings.dock.showIndicators ? 1 : 0

        Behavior on width {
            NumberAnimation { duration: 350; easing.type: Easing.OutQuint }
        }
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
    }

    MouseArea {
        id: itemMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                item.activate()
            } else if (mouse.button === Qt.MiddleButton) {
                item.launch()
            } else if (mouse.button === Qt.RightButton) {
                if (!item.dockWindow)
                    return
                // A second right click on the same icon closes the menu again.
                if (item.menuOpen) {
                    item.dockWindow.closeMenu()
                    return
                }
                tooltipTimer.stop()
                tooltip.visible = false
                item.dockWindow.openMenuFor(item, item.menuActions())
            }
        }

        onEntered: tooltipTimer.restart()
        onExited: {
            tooltipTimer.stop()
            tooltip.visible = false
        }
    }

    // --- TOOLTIP ---
    Timer {
        id: tooltipTimer
        interval: 150
        onTriggered: {
            if (itemMouse.containsMouse && !item.menuOpen)
                tooltip.visible = true
        }
    }

    PopupWindow {
        id: tooltip

        color: "transparent"
        implicitWidth: tooltipBg.implicitWidth
        implicitHeight: tooltipBg.implicitHeight

        // A partial anchor.rect collapses the anchor rectangle and the popup
        // never shows — the gap has to come from margins (see DockMenu).
        anchor.item: item
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        // Clear the magnified icon, which reaches above the item.
        anchor.margins.bottom: 6 + item.iconSize * (item.magnification - 1)

        Rectangle {
            id: tooltipBg
            anchors.centerIn: parent
            implicitWidth: tooltipText.implicitWidth + 20
            implicitHeight: tooltipText.implicitHeight + 12
            radius: 6
            color: Qt.rgba(0.12, 0.12, 0.12, 0.92)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)

            Text {
                textFormat: Text.PlainText
                id: tooltipText
                anchors.centerIn: parent
                text: item.windows.length > 1
                    ? item.appName + " (" + item.windows.length + ")"
                    : item.appName
                color: "#ffffff"
                font.family: "SF Pro Text"
                font.pixelSize: 13
            }
        }
    }

}
