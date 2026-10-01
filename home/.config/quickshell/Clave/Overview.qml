import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

// Overview. The windows of the current Space shrink out of their
// real positions into a grid over the dimmed wallpaper, with a Spaces bar of
// live-ish desktop thumbnails along the top.
//
//   click a window        focus it and zoom back
//   click a Space         switch to it
//   drag a window         onto a Space to move it there
//   "+"                   open a new, empty Space
//   Esc / empty area      leave
//
// Opened by the three-finger swipe up (hypr/gestures.lua), the top-left hot
// corner (HotCorners.qml) and:
//   qs ipc call overview toggle | open | close
Scope {
    id: root

    // The overlay exists only while Overview is up.
    property bool active: false
    // 0 = every window where it really is, 1 = Overview layout. The
    // wallpaper dims in with the same value, so at 0 the overlay is invisible.
    property real progress: 0
    // Whole-overlay opacity, for leaving by fading (switching Space).
    property real fade: 1
    property bool closing: false
    property bool loading: false

    property var monitor: null
    property var targetScreen: null
    property real screenW: 1920
    property real screenH: 1200
    property int activeWs: 1
    property string wallpaper: ""

    // Windows of the current Space: { address, appId, title, toplevel, rect }
    property var windows: []
    // Layout target of each window, by address. Replaced (not the window list)
    // when a window leaves, so the others glide into the gap.
    property var grid: ({})
    property var gone: ({})
    // Spaces on this screen: { id, name, windows: [{ address, toplevel, rect }] }
    property var spaces: []

    readonly property string fontFamily: "Inter"
    readonly property int openDuration: 380
    readonly property int closeDuration: 300

    // Spaces bar geometry, shared by the layout and the bar.
    readonly property real thumbH: Math.round(screenH * 0.105)
    readonly property real thumbW: Math.round(thumbH * screenW / screenH)
    readonly property real barTop: 22
    readonly property real barH: barTop + thumbH + 30

    function normalize(address: string): string {
        const a = `${address ?? ""}`
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a)
    }

    function toplevelFor(address: string): var {
        const list = Hyprland.toplevels.values
        for (let i = 0; i < list.length; i++)
            if (root.normalize(`${list[i].address}`) === address)
                return list[i]
        return null
    }

    function hypr(lua: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", lua])
    }

    function open(): void {
        if (root.active || root.loading)
            return
        root.loading = true
        snapshot.refresh = false
        snapshot.running = true
    }

    // Zooms back out. With an address, that window gets the focus first.
    function close(address: string): void {
        if (!root.active || root.closing)
            return
        root.closing = true
        startAnim.stop()
        if (address)
            root.hypr(`hl.dsp.focus({ window = "address:${address}" })`)
        openAnim.stop()
        closeAnim.start()
    }

    // Leaves by fading, for when the screen underneath changes (another Space).
    function fadeOut(): void {
        if (!root.active || root.closing)
            return
        root.closing = true
        startAnim.stop()
        openAnim.stop()
        fadeAnim.start()
    }

    function finish(): void {
        root.active = false
        root.closing = false
        root.progress = 0
        root.fade = 1
        root.windows = []
        root.spaces = []
        root.grid = ({})
        root.gone = ({})
    }

    function switchTo(wsId: int): void {
        if (wsId === root.activeWs) {
            root.close("")
            return
        }
        root.hypr(`hl.dsp.focus({ workspace = ${wsId}, on_current_monitor = true })`)
        root.fadeOut()
    }

    function newSpace(): void {
        let used = {}
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++)
            used[list[i].id] = true
        let id = 1
        while (used[id])
            id++
        root.switchTo(id)
    }

    function moveToSpace(address: string, wsId: int): void {
        if (wsId === root.activeWs)
            return
        root.hypr(`hl.dsp.window.move({ workspace = "${wsId}", follow = false, window = "address:${address}" })`)
        root.gone = Object.assign({}, root.gone, { [address]: true })
        root.grid = root.layout(root.windows.filter(w => !root.gone[w.address]))
        refreshAfterMove.restart()
    }

    // Rows of windows scaled together, in reading order of where they are
    // now, trying every row count and keeping the one that shows them largest.
    function layout(wins: var): var {
        let out = ({})
        const n = wins.length
        if (n === 0)
            return out
        const gap = 36
        const area = {
            "x": 60, "y": root.barH + 30,
            "w": root.screenW - 120, "h": root.screenH - root.barH - 90
        }
        const sorted = wins.slice().sort((a, b) =>
            (a.rect.y + a.rect.h / 2) - (b.rect.y + b.rect.h / 2) || a.rect.x - b.rect.x)
        let best = null
        for (let rows = 1; rows <= n; rows++) {
            const per = Math.ceil(n / rows)
            let rowList = []
            for (let i = 0; i < n; i += per)
                rowList.push(sorted.slice(i, i + per).sort((a, b) => a.rect.x - b.rect.x))
            let s = 1
            let totalH = 0
            for (const row of rowList) {
                const w = row.reduce((acc, c) => acc + c.rect.w, 0)
                s = Math.min(s, (area.w - gap * (row.length - 1)) / w)
                totalH += Math.max(...row.map(c => c.rect.h))
            }
            s = Math.min(s, (area.h - gap * (rowList.length - 1)) / totalH)
            if (!best || s > best.s + 0.001)
                best = { "s": s, "rows": rowList }
        }
        // Even a lone window shrinks a little.
        const s = Math.min(best.s, 0.78)
        const heights = best.rows.map(r => Math.max(...r.map(c => c.rect.h)) * s)
        const total = heights.reduce((a, b) => a + b, 0) + gap * (heights.length - 1)
        let y = area.y + (area.h - total) / 2
        best.rows.forEach((row, i) => {
            const rowW = row.reduce((a, c) => a + c.rect.w * s, 0) + gap * (row.length - 1)
            let x = area.x + (area.w - rowW) / 2
            for (const c of row) {
                const h = c.rect.h * s
                out[c.address] = { "x": x, "y": y + (heights[i] - h) / 2, "w": c.rect.w * s, "h": h }
                x += c.rect.w * s + gap
            }
            y += heights[i] + gap
        })
        return out
    }

    // Hyprland state in one go: monitors, clients, workspaces, then the
    // wallpaper from awww, separated by marker lines.
    Process {
        id: snapshot
        property bool refresh: false
        command: ["sh", "-c",
            "hyprctl -j monitors; echo '@@@'; hyprctl -j clients; echo '@@@'; hyprctl -j workspaces; echo '@@@'; awww query 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.load(this.text, snapshot.refresh)
        }
    }

    Timer {
        id: refreshAfterMove
        interval: 150
        onTriggered: {
            snapshot.refresh = true
            snapshot.running = true
        }
    }

    function load(text: string, refresh: bool): void {
        root.loading = false
        const parts = text.split("@@@")
        let monitors = [], clients = [], workspaces = []
        try {
            monitors = JSON.parse(parts[0])
            clients = JSON.parse(parts[1])
            workspaces = JSON.parse(parts[2])
        } catch (e) {
            return
        }
        const m = monitors.find(x => x.focused) || monitors[0]
        if (!m)
            return
        const rotated = m.transform % 2 === 1
        const w = (rotated ? m.height : m.width) / m.scale
        const h = (rotated ? m.width : m.height) / m.scale
        const wsId = m.activeWorkspace.id

        const toRect = c => ({ "x": c.at[0] - m.x, "y": c.at[1] - m.y, "w": c.size[0], "h": c.size[1] })
        const onScreen = c => c.mapped && !c.hidden && c.monitor === m.id

        let spaces = workspaces
            .filter(ws => ws.monitorID === m.id && ws.id > 0)
            .sort((a, b) => a.id - b.id)
            .map(ws => ({
                "id": ws.id,
                "name": ws.name,
                "windows": clients
                    .filter(c => onScreen(c) && c.workspace.id === ws.id)
                    .sort((a, b) => (a.floating ? 1 : 0) - (b.floating ? 1 : 0))
                    .map(c => ({ "address": c.address, "toplevel": root.toplevelFor(c.address), "rect": toRect(c) }))
            }))
        root.spaces = spaces

        if (refresh)
            return

        const wall = (parts[3] || "").match(new RegExp(m.name + ":.*?image: (.*)$", "m"))
        root.wallpaper = wall ? wall[1].trim() : ""
        root.monitor = m
        root.targetScreen = Quickshell.screens.find(s => s.name === m.name) || Quickshell.screens[0]
        root.screenW = w
        root.screenH = h
        root.activeWs = wsId

        // A special workspace shown on top means the normal one is hidden.
        const special = m.specialWorkspace && m.specialWorkspace.id !== 0
        root.windows = special ? [] : clients
            .filter(c => onScreen(c) && c.workspace.id === wsId)
            .map(c => ({
                "address": c.address,
                "appId": c.class,
                "title": c.title,
                "toplevel": root.toplevelFor(c.address),
                "rect": toRect(c)
            }))
        root.grid = root.layout(root.windows)
        root.gone = ({})
        root.progress = 0
        root.fade = 1
        root.closing = false
        root.captured = 0
        root.active = true
        startAnim.restart()
    }

    // Waits for the first frame of every window before zooming, so no window
    // blinks out between the real one being covered and its copy appearing.
    property int captured: 0
    onCapturedChanged: if (root.active && root.captured >= root.windows.length && startAnim.running) {
        startAnim.stop()
        openAnim.start()
    }
    Timer {
        id: startAnim
        interval: 180
        onTriggered: openAnim.start()
    }

    NumberAnimation {
        id: openAnim
        target: root
        property: "progress"
        to: 1
        duration: root.openDuration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeAnim
        target: root
        property: "progress"
        to: 0
        duration: root.closeDuration
        easing.type: Easing.InOutCubic
        onFinished: root.finish()
    }
    NumberAnimation {
        id: fadeAnim
        target: root
        property: "fade"
        to: 0
        duration: 220
        easing.type: Easing.OutQuad
        onFinished: root.finish()
    }

    IpcHandler {
        target: "overview"
        function open(): void { root.open() }
        function close(): void { root.close("") }
        function toggle(): void {
            if (root.active)
                root.close("")
            else
                root.open()
        }
    }

    LazyLoader {
        active: root.active

        PanelWindow {
            id: win
            screen: root.targetScreen
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "clave-overview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            // Space under a point in window coordinates, or -1.
            function spaceAt(px: real, py: real): int {
                for (let i = 0; i < spaceRepeater.count; i++) {
                    const it = spaceRepeater.itemAt(i)
                    if (!it)
                        continue
                    const p = it.mapFromItem(null, px, py)
                    if (p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height)
                        return it.modelData.id
                }
                return -1
            }
            property int dropTarget: -1

            Item {
                id: content
                anchors.fill: parent
                opacity: root.fade
                focus: true
                Keys.onEscapePressed: root.close("")

                // Dimmed wallpaper
                Item {
                    anchors.fill: parent
                    opacity: root.progress
                    Image {
                        anchors.fill: parent
                        source: root.wallpaper ? "file://" + root.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(0, 0, 0, 0.42)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close("")
                }

                // ==========================================
                // SPACES BAR
                // ==========================================
                Item {
                    id: bar
                    x: 0
                    y: root.barTop - (1 - root.progress) * (root.barH + 10)
                    width: parent.width
                    height: root.thumbH + 30
                    opacity: root.progress

                    Row {
                        id: spaceRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 22

                        Repeater {
                            id: spaceRepeater
                            model: root.spaces

                            Item {
                                id: space
                                required property var modelData
                                readonly property bool current: modelData.id === root.activeWs
                                readonly property bool hot: spaceMouse.containsMouse || win.dropTarget === modelData.id
                                width: root.thumbW
                                height: root.thumbH + 26

                                Rectangle {
                                    id: frame
                                    width: root.thumbW
                                    height: root.thumbH
                                    radius: 8
                                    color: "transparent"
                                    border.width: space.current || space.hot ? 2.5 : 0
                                    border.color: space.hot && !space.current ? Qt.rgba(1, 1, 1, 0.6) : "#ffffff"
                                    scale: space.hot ? 1.04 : 1
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        anchors.margins: frame.border.width > 0 ? 3 : 0
                                        radius: 6
                                        color: "#1c1c1e"

                                        Image {
                                            anchors.fill: parent
                                            source: root.wallpaper ? "file://" + root.wallpaper : ""
                                            sourceSize.width: root.thumbW * 2
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }

                                        Item {
                                            id: mini
                                            anchors.fill: parent
                                            readonly property real s: width / root.screenW
                                            Repeater {
                                                model: space.modelData.windows
                                                ClippingRectangle {
                                                    id: miniWin
                                                    required property var modelData
                                                    visible: !root.gone[modelData.address] || !space.current
                                                    x: modelData.rect.x * mini.s
                                                    y: modelData.rect.y * mini.s
                                                    width: modelData.rect.w * mini.s
                                                    height: modelData.rect.h * mini.s
                                                    radius: 2
                                                    color: Qt.rgba(1, 1, 1, 0.12)
                                                    ScreencopyView {
                                                        anchors.fill: parent
                                                        captureSource: miniWin.modelData.toplevel ? miniWin.modelData.toplevel.wayland : null
                                                        live: false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.horizontalCenter: frame.horizontalCenter
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 7
                                    text: "Desktop " + space.modelData.name
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: space.current ? Font.DemiBold : Font.Normal
                                    opacity: space.current || space.hot ? 1 : 0.75
                                }

                                MouseArea {
                                    id: spaceMouse
                                    anchors.fill: frame
                                    hoverEnabled: true
                                    onClicked: root.switchTo(space.modelData.id)
                                }
                            }
                        }

                        // New Space
                        Item {
                            width: root.thumbH * 0.62
                            height: root.thumbH
                            opacity: barHover.hovered ? 1 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: addMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.pixelSize: 30
                                    font.weight: Font.Light
                                }
                            }
                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.newSpace()
                            }
                        }
                    }

                    HoverHandler { id: barHover }
                }

                // ==========================================
                // WINDOWS
                // ==========================================
                Repeater {
                    model: root.windows

                    Item {
                        id: tile
                        required property var modelData
                        readonly property var r: modelData.rect
                        readonly property var target: root.grid[modelData.address] || r
                        readonly property bool leaving: !!root.gone[modelData.address]

                        // Layout target, animated when a neighbour leaves.
                        property real gx: target.x
                        property real gy: target.y
                        property real gw: target.w
                        property real gh: target.h
                        Behavior on gx { enabled: root.progress === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on gy { enabled: root.progress === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on gw { enabled: root.progress === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on gh { enabled: root.progress === 1; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        // Offset while being dragged.
                        property real dx: 0
                        property real dy: 0
                        property bool dragging: false

                        readonly property real p: root.progress
                        x: r.x + (gx - r.x) * p + dx
                        y: r.y + (gy - r.y) * p + dy
                        width: r.w + (gw - r.w) * p
                        height: r.h + (gh - r.h) * p
                        visible: !leaving
                        z: dragging ? 10 : 1
                        scale: dragging ? 0.6 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                        readonly property bool hot: tileMouse.containsMouse && root.progress === 1 && !root.closing

                        // Hover outline
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 14
                            color: "transparent"
                            border.width: 3
                            border.color: Qt.rgba(1, 1, 1, 0.85)
                            opacity: tile.hot && !tile.dragging ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 12 - 2 * tile.p
                            color: "transparent"
                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: tile.modelData.toplevel ? tile.modelData.toplevel.wayland : null
                                live: true
                                property bool counted: false
                                onHasContentChanged: if (hasContent && !counted) {
                                    counted = true
                                    root.captured++
                                }
                                Component.onCompleted: if (!captureSource) root.captured++
                            }
                        }

                        // Title under the hovered window
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 10
                            width: Math.min(titleRow.implicitWidth + 20, Math.max(parent.width, 180))
                            height: 24
                            radius: 12
                            color: Qt.rgba(0.12, 0.12, 0.13, 0.85)
                            opacity: tile.hot && !tile.dragging ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Row {
                                id: titleRow
                                anchors.centerIn: parent
                                spacing: 6
                                width: Math.min(implicitWidth, parent.width - 20)
                                clip: true
                                IconImage {
                                    implicitSize: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: {
                                        const id = ClaveSettings.windowAppId(tile.modelData.appId, tile.modelData.title)
                                        const e = DesktopEntries.heuristicLookup(id)
                                        return Quickshell.iconPath(e && e.icon ? e.icon : id, "application-x-executable")
                                    }
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tile.modelData.title || tile.modelData.appId
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, titleRow.parent.width - 42)
                                }
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            property point start
                            // Set by a drag, so the release does not also count as a click.
                            property bool dragged: false
                            onPressed: mouse => {
                                dragged = false
                                start = mapToItem(null, mouse.x, mouse.y)
                            }
                            onPositionChanged: mouse => {
                                if (!pressed || root.progress < 1)
                                    return
                                const pt = mapToItem(null, mouse.x, mouse.y)
                                if (!tile.dragging && Math.hypot(pt.x - start.x, pt.y - start.y) > 8)
                                    tile.dragging = true
                                if (tile.dragging) {
                                    tile.dx += pt.x - start.x
                                    tile.dy += pt.y - start.y
                                    start = pt
                                    win.dropTarget = win.spaceAt(pt.x, pt.y)
                                }
                            }
                            onReleased: mouse => {
                                if (!tile.dragging)
                                    return
                                const target = win.dropTarget
                                win.dropTarget = -1
                                tile.dragging = false
                                dragged = true
                                if (target !== -1 && target !== root.activeWs) {
                                    root.moveToSpace(tile.modelData.address, target)
                                } else {
                                    snapBack.start()
                                }
                            }
                            onClicked: {
                                if (!dragged && root.progress === 1)
                                    root.close(tile.modelData.address)
                            }
                        }

                        ParallelAnimation {
                            id: snapBack
                            NumberAnimation { target: tile; property: "dx"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: tile; property: "dy"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }
}
