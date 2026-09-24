import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.CustomTheme
import qs.DockApp

// Application dock: the running Hyprland applications plus a persistent list of 
// pinned ones, on a single (primary) screen at the bottom edge.
PanelWindow {
    id: root

    // Pinned apps | running apps that are not pinned | Trash, with a thin
    // separator between the groups, like the macOS dock.
    component DockSeparator: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        implicitWidth: 1
        implicitHeight: root.settings.dock.iconSize * 0.8
        color: Qt.rgba(1, 1, 1, 0.25)
    }


    // --- WAYLAND CONFIGURATION ---
    WlrLayershell.layer: WlrLayer.Top
    // Hyprland blurs this namespace (see hypr/custom.lua, macOS block).
    WlrLayershell.namespace: "macos-dock"
    // The dock claims its strip of the screen so windows tile above it instead
    // of running underneath. Only the pill itself is reserved (the window is
    // taller to leave room for the shadow), see exclusiveZone below.
    //
    // Autohiding and reserving space are mutually exclusive — a hidden dock that
    // still holds a gap open would be pointless — so an autohiding dock (or one
    // with dock.reserveSpace turned off) goes back to floating over the windows.
    exclusionMode: root.reservesSpace
        ? ExclusionMode.Normal
        : ExclusionMode.Ignore

    // DockLoader sets this to put one dock on each screen. When unset, the dock
    // goes on the primary screen: the Hyprland monitor with id 0, matched
    // to a Quickshell screen by name. Falls back to the first known screen.
    property var targetScreen: null
    screen: {
        if (targetScreen)
            return targetScreen
        const screens = Quickshell.screens
        if (!screens || screens.length === 0)
            return null
        const monitors = Hyprland.monitors.values
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].id !== 0)
                continue
            for (let s = 0; s < screens.length; s++)
                if (screens[s].name === monitors[i].name)
                    return screens[s]
        }
        return screens[0]
    }

    // --- USER SETTINGS ---
    // Read and written by the DockSettings singleton, which owns the settings
    // files. It lives outside this window because dock.enabled decides whether
    // the window is created at all (see DockLoader).
    readonly property var settings: DockSettings.settings

    // --- PINNING ---
    readonly property var pinnedApps: settings.apps.pinned

    // Compared on resolved keys, not on the raw strings: a stored id may be an
    // executable name ("claude-desktop") while the key is the desktop entry id
    // it resolves to (com.anthropic.Claude).
    function isPinned(key: string): bool {
        const pinned = root.pinnedApps
        for (let i = 0; i < pinned.length; i++)
            if (root.entryKey(pinned[i]) === key)
                return true
        return false
    }

    // Append an app to the pinned list (it keeps its position from then on).
    function pinApp(key: string): void {
        if (!key || root.isPinned(key))
            return
        DockSettings.persistPinned(root.pinnedApps.concat([key]))
    }

    function unpinApp(key: string): void {
        if (!key)
            return
        DockSettings.persistPinned(
            root.pinnedApps.filter(id => root.entryKey(id) !== key))
    }

    // --- APP MODEL ---
    // The desktop entry for a window's app id or a pinned id, or null.
    function lookupEntry(appId: string): var {
        if (!appId)
            return null
        const direct = DesktopEntries.heuristicLookup(appId)
        if (direct)
            return direct
        // Pinned ids inherited from nwg-dock are executable names
        // ("claude-desktop"), which heuristicLookup does not match against an
        // entry named differently (com.anthropic.Claude). Fall back to the first
        // entry whose command runs that executable.
        const wanted = appId.toLowerCase()
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            const command = apps[i].command
            if (!command || command.length === 0)
                continue
            if (`${command[0]}`.split("/").pop().toLowerCase() === wanted)
                return apps[i]
        }
        return null
    }

    // Group key shared by windows and pinned entries: the desktop entry id when
    // one can be found for the window's app id (so "org.mozilla.firefox",
    // "firefox" and the pinned "firefox" all land in the same slot), otherwise
    // the lowercased app id.
    function entryKey(appId: string): string {
        if (!appId)
            return ""
        const entry = root.lookupEntry(appId)
        return entry ? entry.id : appId.toLowerCase()
    }

    // Icon file for an app: the desktop entry's icon when there is one,
    // otherwise the app id itself as an icon-theme name — which is how apps
    // without an installed desktop entry (e.g. a pinned "obsidian") still get
    // their themed icon. The provider prefix and query string a desktop entry
    // may carry are stripped, the same way the overview does it.
    function iconFor(entry: var, appId: string): string {
        const raw = `${entry?.icon ?? ""}`.trim()
            .replace(/^image:\/\/icon\//, "").split("?")[0].trim()
        const name = raw.length > 0 ? raw : (appId ? appId : "")
        // Desktop entries may point at an icon file instead of a theme name.
        if (name.startsWith("/"))
            return "file://" + name
        return Quickshell.iconPath(
            name.length > 0 ? name : "application-x-executable",
            "application-x-executable")
    }

    // The dock's items: the pinned apps first, in their stored order, followed
    // by the running apps that are not pinned. Each item groups all windows of
    // one app and carries everything the delegate needs to draw it:
    //   { key, appId, desktopEntry, name, iconSource, windows: [Toplevel], pinned }
    readonly property var dockEntries: {
        DesktopEntries.applications.values   // re-run when the entry index updates
        const toplevels = ToplevelManager.toplevels.values
        let byKey = ({})
        let order = []

        function makeItem(key, appId, pinned) {
            const desktopEntry = root.lookupEntry(appId)
            const name = desktopEntry && desktopEntry.name.length > 0
                ? desktopEntry.name : appId
            return { "key": key, "appId": appId, "desktopEntry": desktopEntry,
                     "name": name, "iconSource": root.iconFor(desktopEntry, appId),
                     "windows": [], "pinned": pinned }
        }

        const pinned = root.pinnedApps
        for (let i = 0; i < pinned.length; i++) {
            const key = root.entryKey(pinned[i])
            if (key === "" || byKey[key] !== undefined)
                continue
            byKey[key] = makeItem(key, pinned[i], true)
            order.push(key)
        }

        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i]
            const key = root.entryKey(toplevel.appId)
            if (key === "")
                continue
            if (byKey[key] === undefined) {
                byKey[key] = makeItem(key, toplevel.appId, false)
                order.push(key)
            }
            byKey[key].windows.push(toplevel)
        }

        return order.map(key => byKey[key])
    }

    // --- VISIBILITY ---
    // This window exists only while the dock is enabled — DockLoader creates and
    // destroys it with the flag — so there is nothing to hide here.
    property bool autohide: settings.dock.autohide

    // Whether the dock holds a gap open at the bottom of the screen.
    readonly property bool reservesSpace: settings.dock.reserveSpace && !autohide
    // The pill plus its bottom margin — not the full window height, which also
    // covers the drop shadow and the slide-out distance.
    exclusiveZone: reservesSpace ? dockHeight + settings.dock.marginBottom : 0

    // --- CONTEXT MENU ---
    // One menu for the whole dock, drawn inside this window above the item it
    // was opened from. Only one can be open, so right-clicking another icon just
    // moves it.
    property var menuItem: null
    readonly property bool menuOpen: contextMenu.visible

    function openMenuFor(item, actions): void {
        root.menuItem = item
        contextMenu.actions = actions
        contextMenu.visible = true
    }

    function closeMenu(): void {
        contextMenu.visible = false
        root.menuItem = null
    }

    // Dismiss the menu when the pointer or keyboard goes to another window. The
    // grab is held on this window (a layer surface), so clicks on the dock and
    // on the menu itself still arrive normally.
    HyprlandFocusGrab {
        windows: [root]
        active: contextMenu.visible
        onCleared: root.closeMenu()
    }

    // Slid into view when autohide is off, while the pointer is on the dock (or
    // in the hot zone at the screen edge), and while a context menu is open.
    readonly property bool revealed: !autohide || root.pointerHeld
        || root.menuOpen

    // The pointer's hover, held for dock.hideDelay ms after it leaves. Without
    // the grace period the dock snaps shut on every momentary gap in the hover:
    // crossing from the hot zone up to the still-sliding pill, slipping between
    // the pill and the screen edge, or brushing past the edge of the pill.
    property bool pointerHeld: false

    Timer {
        id: hideDelay
        interval: root.settings.dock.hideDelay
        onTriggered: root.pointerHeld = false
    }

    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    // Height of the visible pill, and of the window around it. The window is
    // taller than the pill to leave room for the drop shadow and for the pill to
    // slide down out of view when autohiding.
    readonly property int dockHeight: settings.dock.iconSize
        + 2 * settings.pill.padding + 10
    // Room above the pill for the context menu, which is drawn inside this
    // window. It is reserved permanently rather than added when a menu opens:
    // resizing the layer surface on open/close makes the whole dock flicker.
    // The area stays transparent and click-through (see mask), and the reserved
    // space (exclusiveZone) is set explicitly, so the extra height costs
    // nothing. Sized for the tallest menu: three 32px rows, 2px apart, in a box
    // with 8px padding, plus the 8px gap above the pill.
    readonly property int menuReserve: 3 * 32 + 2 * 2 + 16 + 8
    implicitHeight: dockHeight + settings.dock.marginBottom + 30 + menuReserve

    // Only the pill takes pointer input; the transparent rest of the window
    // stays click-through so it never swallows clicks meant for the windows
    // behind it. While a menu is open the whole window takes input, so the menu
    // entries are clickable and a click on the dock's empty area dismisses the
    // menu.
    //
    // While autohiding, a full-width strip at the screen edge stays active on
    // top of the pill: hidden it is the hot zone that reveals the dock, revealed
    // it bridges the marginBottom gap below the pill. The strip has to keep
    // taking input after the reveal, or the pointer that triggered it — still at
    // the very bottom of the screen, and possibly nowhere near the pill
    // horizontally — would land outside the input region and hide the dock right
    // back again.
    readonly property int hotZoneHeight: root.revealed
        ? settings.dock.marginBottom + 3
        : 3

    mask: Region {
        Region {
            x: 0
            y: 0
            width: root.menuOpen ? root.width : 0
            height: root.menuOpen ? root.height : 0
        }
        // The pill. While hidden it is a 3px sliver at the screen edge, which
        // the hot zone covers anyway.
        Region {
            x: Math.round(pill.x)
            y: Math.round(pill.y)
            width: root.menuOpen ? 0 : Math.round(pill.width)
            height: root.menuOpen ? 0 : Math.round(pill.height)
        }
        Region {
            x: Math.round(pill.x)
            y: Math.round(pill.y - root.magnifyOverhang)
            width: root.magnifying ? Math.round(pill.width) : 0
            height: root.magnifying ? Math.ceil(root.magnifyOverhang) : 0
        }
        Region {
            x: 0
            y: root.height - root.hotZoneHeight
            width: (root.autohide && !root.menuOpen) ? root.width : 0
            height: (root.autohide && !root.menuOpen) ? root.hotZoneHeight : 0
        }
    }

    // A click anywhere in the dock window that is not on the menu or an icon
    // closes the menu (the focus grab only covers clicks in other windows).
    MouseArea {
        anchors.fill: parent
        enabled: root.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeMenu()
    }

    HoverHandler {
        id: dockHover
        onHoveredChanged: {
            if (dockHover.hovered) {
                hideDelay.stop()
                root.pointerHeld = true
            } else {
                hideDelay.restart()
            }
        }
    }

    // --- MAGNIFICATION ---
    // macOS hover magnification: icons near the pointer grow and push their
    // neighbours apart. The scale is worked out against each icon's resting
    // position (DockItem.baseCenter), not its live one, so growing icons never
    // feed back into the calculation and the row stays still under the pointer.
    readonly property var magnify: settings.magnification
    // How far a fully magnified icon reaches above the pill. That strip takes
    // input while magnifying so the pointer can sit on the top of a big icon.
    readonly property real magnifyOverhang: settings.dock.iconSize
        * (magnify.maxScale - 1)
    readonly property real pointerX: dockHover.point.position.x
    readonly property real pointerY: dockHover.point.position.y
    readonly property bool magnifying: magnify.enabled && dockHover.hovered
        && !root.menuOpen && root.revealed
        && pointerY >= pill.y - magnifyOverhang
        && pointerX >= pill.x && pointerX <= pill.x + pill.width

    // Keeps the pill from easing its width while the icons settle back.
    Timer { id: magnifySettle; interval: 250 }
    onMagnifyingChanged: if (!magnifying) magnifySettle.restart()

    // Resting center (window coordinates) of a dock item.
    function centerOf(it: Item): real {
        return pill.x + dockRow.x + it.x + it.width / 2
    }

    // Scale for an icon resting at `center`: cosine falloff over `range` icons.
    function magnifyFor(center: real): real {
        if (!root.magnifying)
            return 1
        const reach = root.magnify.range * root.settings.dock.iconSize
        const d = Math.abs(root.pointerX - center)
        if (d >= reach)
            return 1
        return 1 + (root.magnify.maxScale - 1) * (1 + Math.cos(Math.PI * d / reach)) / 2
    }

    // ==========================================
    // DOCK PILL
    // ==========================================
    Item {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        width: dockRow.implicitWidth + 2 * root.settings.pill.padding
        height: root.dockHeight

        // Gap between the pill's bottom edge and the window's, animated for the
        // autohide slide. The pill's y is derived from it rather than animated
        // directly, so the window growing to fit a context menu repositions the
        // pill instantly instead of sliding it.
        property real revealOffset: root.revealed
            ? root.settings.dock.marginBottom
            : -(height - 3)

        Behavior on revealOffset {
            NumberAnimation {
                duration: root.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        y: parent.height - height - revealOffset

        Behavior on width {
            enabled: !root.magnifying && !magnifySettle.running
            NumberAnimation {
                duration: root.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        RectangularShadow {
            anchors.fill: pillBg
            radius: pillBg.radius
            blur: 18
            color: Qt.rgba(0, 0, 0, 0.3)
        }

        // macOS glass: translucent fill (Hyprland blurs behind it) with a
        // hairline light border.
        Rectangle {
            id: pillBg
            anchors.fill: parent
            radius: root.settings.pill.radius
            color: Qt.rgba(0.16, 0.16, 0.16, 0.35)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }

        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: root.settings.dock.spacing

            Repeater {
                model: root.dockEntries.filter(e => e.pinned)
                delegate: dockDelegate
            }

            DockSeparator { visible: root.dockEntries.some(e => !e.pinned) }

            Repeater {
                model: root.dockEntries.filter(e => !e.pinned)
                delegate: dockDelegate
            }

            DockSeparator {}

            // Trash: empty/full icon, opens the trash in the file manager.
            Item {
                id: trash
                property bool full: false
                property real baseCenter: 0
                readonly property real liveCenter: root.centerOf(trash)
                onLiveCenterChanged: if (!root.magnifying) baseCenter = liveCenter
                Component.onCompleted: baseCenter = liveCenter
                property real magnification: root.magnifyFor(trash.baseCenter)
                Behavior on magnification {
                    NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                }
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.settings.dock.iconSize * trash.magnification + 16
                implicitHeight: root.settings.dock.iconSize + 18

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: root.settings.dock.iconSize * trash.magnification
                    height: width
                    sourceSize.width: root.settings.dock.iconSize * 3
                    sourceSize.height: root.settings.dock.iconSize * 3
                    source: Quickshell.iconPath(trash.full ? "user-trash-full" : "user-trash", "user-trash")
                    opacity: trashMouse.pressed ? 0.6 : 1
                }

                MouseArea {
                    id: trashMouse
                    anchors.fill: parent
                    onClicked: Quickshell.execDetached(["nautilus", "trash:///"])
                }

                Process {
                    id: trashProbe
                    running: true
                    command: ["bash", "-c", "[ -n \"$(ls -A ~/.local/share/Trash/files 2>/dev/null)\" ] && echo 1 || echo 0"]
                    stdout: StdioCollector { onStreamFinished: trash.full = this.text.trim() === "1" }
                }
                Timer { interval: 5000; running: true; repeat: true; onTriggered: trashProbe.running = true }
            }
        }

        Component {
            id: dockDelegate
            DockItem {
                required property var modelData

                entry: modelData
                iconSize: root.settings.dock.iconSize
                dockWindow: root
                Layout.alignment: Qt.AlignVCenter

                onPinRequested: key => root.pinApp(key)
                onUnpinRequested: key => root.unpinApp(key)
            }
        }
    }

    // ==========================================
    // GENIE (minimize / restore animation)
    // ==========================================
    // Screen rectangle of the dock icon a window belongs to. Falls back to the
    // middle of the pill for a window with no icon.
    function iconRectFor(ht: var): rect {
        const key = ht && ht.wayland ? root.entryKey(ht.wayland.appId) : ""
        const top = root.screen.height - root.height
        const kids = dockRow.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (!c.entry || c.entry.key !== key || !c.iconItem)
                continue
            const p = c.iconItem.mapToItem(null, 0, 0)
            return Qt.rect(p.x, top + p.y, c.iconItem.width, c.iconItem.height)
        }
        const size = root.settings.dock.iconSize
        return Qt.rect(pill.x + pill.width / 2 - size / 2,
                       top + pill.y + (pill.height - size) / 2, size, size)
    }

    // Takes the requests for windows on this dock's screen.
    function onThisScreen(ht: var): bool {
        const mon = ht.monitor ?? ht.workspace?.monitor
        return !!mon && !!root.screen && mon.name === root.screen.name
    }

    GenieOverlay {
        id: genieOverlay
        screen: root.screen
        iconRectFor: ht => root.iconRectFor(ht)
    }

    Connections {
        target: Minimizer
        function onMinimizeRequested(ht, address) {
            if (Minimizer.claimed || !root.onThisScreen(ht))
                return
            Minimizer.claim()
            genieOverlay.minimize(ht, address)
        }
        // A minimized window sits on special:minimized, whose monitor is where
        // it was last shown; restore it through the dock of the focused screen.
        function onRestoreRequested(ht, address, workspace, focus) {
            const mon = Hyprland.focusedMonitor
            if (Minimizer.claimed || !mon || !root.screen || mon.name !== root.screen.name)
                return
            Minimizer.claim()
            genieOverlay.restore(ht, address, workspace, focus)
        }
    }

    // ==========================================
    // CONTEXT MENU
    // ==========================================
    // Declared after the pill so it draws on top of it, and centered over the
    // item it belongs to, clamped to stay on screen.
    DockMenu {
        id: contextMenu

        x: {
            if (!root.menuItem)
                return 0
            const center = pill.x + dockRow.x + root.menuItem.x
                + root.menuItem.width / 2
            return Math.max(8, Math.min(root.width - width - 8, center - width / 2))
        }
        y: pill.y - height - 8

        onCloseRequested: root.closeMenu()
    }
}
