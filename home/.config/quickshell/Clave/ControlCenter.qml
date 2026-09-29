import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Control Center, opened from the switches icon in the menu bar:
//
//   [ Wi-Fi / Bluetooth / VPN ] [        Focus        ]
//   [                         ] [ Night Light ][ Mirror ]
//   [ Display brightness                              ]
//   [ Sound                                           ]
//   [ Now Playing                                     ]
//
// Wi-Fi uses nmcli, the VPN row Mullvad's CLI or else the first NetworkManager
// VPN/WireGuard connection, Focus is swaync's Do Not
// Disturb, Night Light runs hyprsunset and Screen Mirroring turns mirroring of
// the built-in screen on or off (clave-displays mirror toggle).
//   qs ipc call controlcenter toggle | open | close
PanelWindow {
    id: root

    WlrLayershell.namespace: "clave-control-center"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors { top: true; right: true }
    margins { top: 6; right: 10 }
    exclusiveZone: 0
    implicitWidth: 336
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: root.shown || fadeOut.running

    readonly property string fontFamily: Theme.fontFamily
    readonly property color accent: Theme.accent
    readonly property string home: Quickshell.env("HOME")

    property bool shown: false
    // The focus grab closes the panel on a click outside it, and that click
    // may be on the menu bar icon, which then toggles it straight back open.
    property real closedAt: 0

    function open(): void {
        if (root.shown)
            return
        status.running = true
        brightnessProc.running = true
        root.shown = true
    }

    function close(): void {
        if (!root.shown)
            return
        root.shown = false
        root.closedAt = Date.now()
    }

    function toggle(): void {
        if (root.shown)
            root.close()
        else if (Date.now() - root.closedAt > 250)
            root.open()
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown
        onCleared: root.close()
    }

    // ==========================================
    // STATE
    // ==========================================
    property bool wifiOn: false
    property string ssid: ""
    // Wired network: shown only on computers with an Ethernet port.
    property bool hasEthernet: false
    property bool ethOn: false
    property string ethDevice: ""
    property string ethName: ""
    property bool vpnOn: false
    property bool hasVpn: false
    property string vpnKind: ""      // "mullvad" or "nm"
    property string vpnName: ""
    property bool dnd: false
    property bool nightLight: false
    property real brightness: 1
    // Keyboard backlight device (e.g. "tpacpi::kbd_backlight"), "" if none.
    property string kbdLight: ""
    property bool kbdOn: false
    Process {
        running: true
        command: ["brightnessctl", "-l", "-m", "-c", "leds"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n").find(l => /kbd_backlight/.test(l.split(",")[0]))
                if (line) {
                    const f = line.split(",")
                    root.kbdLight = f[0]
                    root.kbdOn = parseInt(f[2]) > 0
                }
            }
        }
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: root.adapter !== null && root.adapter.enabled
    readonly property var btConnected: root.adapter
        ? root.adapter.devices.values.filter(d => d.connected) : []

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: root.sink !== null && root.sink.ready && root.sink.audio !== null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // Album art comes from the player. Local files show; web addresses only
    // with System Settings > Privacy & Security > "Load album art from the
    // internet", so a player cannot make the shell fetch URLs by default.
    readonly property string artUrl: {
        const url = root.player ? `${root.player.trackArtUrl || ""}` : ""
        if (url.startsWith("file://"))
            return url
        if (/^https?:\/\//.test(url) && ClaveSettings.get("privacy", "albumArtOnline") === true)
            return url
        return ""
    }

    // The player shown under Now Playing: a playing one if any.
    readonly property var player: {
        const list = Mpris.players.values
        return list.find(p => p.isPlaying) || (list.length > 0 ? list[0] : null)
    }

    // One snapshot of everything command-line driven, as key=value lines.
    Process {
        id: status
        command: ["sh", "-c",
            "echo \"wifi=$(nmcli -t radio wifi 2>/dev/null)\";"
            + "echo \"ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n1)\";"
            + "if command -v mullvad >/dev/null; then echo vpnkind=mullvad; echo \"vpn=$(mullvad status 2>/dev/null | head -n1)\";"
            + "else c=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed -n 's/:\\(vpn\\|wireguard\\)$//p' | head -n1);"
            + " if [ -n \"$c\" ]; then echo vpnkind=nm; echo \"vpnname=$c\";"
            + "  nmcli -t -f NAME connection show --active | grep -qxF \"$c\" && echo vpn=Connected || echo vpn=Disconnected; fi; fi;"
            // eth=STATE:DEVICE:CONNECTION of the first wired device, a connected one first.
            + "nmcli -t -f TYPE,STATE,DEVICE,CONNECTION dev 2>/dev/null | awk -F: '$1 == \"ethernet\" {"
            + " l = $2 \":\" $3 \":\"; if (NF > 3) { sub(/^[^:]*:[^:]*:[^:]*:/, \"\"); l = l $0 }"
            + " if ($2 == \"connected\" && c == \"\") c = l; else if (d == \"\") d = l }"
            + " END { if (c != \"\") print \"eth=\" c; else if (d != \"\") print \"eth=\" d }';"
            + "echo \"dnd=$(swaync-client -D 2>/dev/null)\";"
            + "pgrep -x hyprsunset >/dev/null && echo night=1 || echo night=0"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = ({})
                this.text.split("\n").forEach(line => {
                    const i = line.indexOf("=")
                    if (i > 0)
                        v[line.slice(0, i)] = line.slice(i + 1).trim()
                })
                root.wifiOn = v.wifi === "enabled"
                root.ssid = v.ssid || ""
                root.hasVpn = v.vpn !== undefined
                root.vpnKind = v.vpnkind || ""
                root.vpnName = v.vpnname || ""
                root.vpnOn = v.vpn === "Connected"
                const eth = (v.eth || "").split(":")
                root.hasEthernet = v.eth !== undefined
                root.ethOn = eth[0] === "connected"
                root.ethDevice = eth[1] || ""
                root.ethName = eth.slice(2).join(":").replace(/\\$/, "")
                root.dnd = v.dnd === "true"
                root.nightLight = v.night === "1"
            }
        }
    }
    Timer { id: restatus; interval: 1500; onTriggered: status.running = true }
    // mullvad status takes about a second; have values ready for the first open.
    Component.onCompleted: status.running = true

    Process {
        id: brightnessProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(",")
                if (f.length >= 4)
                    root.brightness = parseInt(f[3]) / 100
            }
        }
    }

    function run(cmd: var): void {
        Quickshell.execDetached(cmd)
        restatus.restart()
    }

    function setBrightness(v: real): void {
        root.brightness = v
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.max(1, Math.round(v * 100)) + "%"])
    }

    // ==========================================
    // PIECES
    // ==========================================
    component Module: Rectangle {
        radius: Theme.radiusCard
        color: Theme.fgA(0.09)
        border.color: Theme.fgA(0.08)
        border.width: 1
    }

    component Circle: Rectangle {
        id: circle
        property string icon: ""
        property bool on: false
        property int size: 30
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: on ? root.accent : Theme.fgA(circleMouse.containsMouse ? 0.24 : 0.16)
        Behavior on color { ColorAnimation { duration: 140 } }
        Image {
            anchors.centerIn: parent
            source: circle.icon
            width: circle.size * 0.52
            height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
        }
        MouseArea {
            id: circleMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: circle.clicked()
        }
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: Theme.fg
        font.family: root.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    component Detail: Text {
        textFormat: Text.PlainText
        color: Theme.fgA(0.55)
        font.family: root.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // Row of the connectivity module: circle, name, state. The text half
    // opens the matching settings.
    component ToggleRow: RowLayout {
        id: tr
        property string icon
        property string label
        property string detail
        property bool on
        signal toggled()
        signal opened()
        spacing: 9
        Circle { icon: tr.icon; on: tr.on; onClicked: tr.toggled() }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Label { text: tr.label; Layout.fillWidth: true }
            Detail { text: tr.detail; Layout.fillWidth: true }
            TapHandler { onTapped: tr.opened() }
        }
    }

    // Slider: a white fill over a dark track, icon at the start.
    component PillSlider: Rectangle {
        id: sl
        property real value: 0
        property string icon: ""
        signal moved(real v)
        implicitHeight: 24
        radius: height / 2
        color: Theme.fgA(0.14)
        Rectangle {
            width: Math.max(sl.height, sl.width * Math.min(1, sl.value))
            height: sl.height
            radius: sl.height / 2
            color: "#ffffff"
        }
        Image {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 13; height: 13
            sourceSize.width: 26; sourceSize.height: 26
            source: sl.icon
            // The glyph sits on the white fill, so draw it dark.
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1
                colorizationColor: "#6e6e73"
            }
        }
        MouseArea {
            anchors.fill: parent
            function setFrom(mx: real): void { sl.moved(Math.max(0, Math.min(1, mx / width))) }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
        }
    }

    // ==========================================
    // PANEL
    // ==========================================
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.panel
        border.color: Theme.border
        border.width: 1

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.96
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { id: fadeOut; duration: root.shown ? 120 : 160; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        focus: true
        Keys.onEscapePressed: root.close()

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // --- top block ---
            RowLayout {
                spacing: 10
                Layout.fillWidth: true

                Module {
                    Layout.preferredWidth: 153
                    // One more row for Ethernet when there is a port as well as a VPN.
                    Layout.preferredHeight: root.hasEthernet && root.hasVpn ? 204 : 158
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 8

                        ToggleRow {
                            Layout.fillWidth: true
                            icon: "icons/wifi.svg"
                            label: "Wi-Fi"
                            detail: !root.wifiOn ? "Off" : root.ssid !== "" ? root.ssid : "Not Connected"
                            on: root.wifiOn
                            onToggled: {
                                root.wifiOn = !root.wifiOn
                                root.run(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"])
                            }
                            onOpened: {
                                root.close()
                                Quickshell.execDetached(["qs", "ipc", "call", "menubar", "open", "wifi"])
                            }
                        }
                        ToggleRow {
                            Layout.fillWidth: true
                            icon: "icons/bluetooth.svg"
                            label: "Bluetooth"
                            detail: !root.btOn ? "Off"
                                  : root.btConnected.length > 0 ? root.btConnected[0].name : "On"
                            on: root.btOn
                            onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                            onOpened: {
                                root.close()
                                Quickshell.execDetached(["blueman-manager"])
                            }
                        }
                        ToggleRow {
                            Layout.fillWidth: true
                            visible: root.hasEthernet
                            icon: "icons/ethernet.svg"
                            label: "Ethernet"
                            detail: root.ethOn ? (root.ethName || "Connected") : "Not Connected"
                            on: root.ethOn
                            onToggled: {
                                root.ethOn = !root.ethOn
                                root.run(["nmcli", "device", root.ethOn ? "connect" : "disconnect", root.ethDevice])
                                restatus.restart()
                            }
                            onOpened: {
                                root.close()
                                Quickshell.execDetached(["nm-connection-editor"])
                            }
                        }
                        ToggleRow {
                            Layout.fillWidth: true
                            visible: root.hasVpn
                            icon: "icons/shield.svg"
                            label: "VPN"
                            detail: !root.vpnOn ? "Not Connected"
                                : root.vpnKind === "mullvad" ? "Mullvad" : root.vpnName
                            on: root.vpnOn
                            onToggled: {
                                root.vpnOn = !root.vpnOn
                                if (root.vpnKind === "mullvad")
                                    root.run(["mullvad", root.vpnOn ? "connect" : "disconnect"])
                                else
                                    root.run(["nmcli", "connection", root.vpnOn ? "up" : "down", "id", root.vpnName])
                            }
                            onOpened: {
                                root.close()
                                Quickshell.execDetached(root.vpnKind === "mullvad" ? ["mullvad-vpn"] : ["nm-connection-editor"])
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                ColumnLayout {
                    spacing: 10
                    Layout.fillWidth: true

                    // Focus
                    Module {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 9
                            Circle {
                                icon: "icons/moon.svg"
                                on: root.dnd
                                color: root.dnd ? Theme.indigo : Theme.fgA(0.16)
                                onClicked: {
                                    root.dnd = !root.dnd
                                    root.run(["swaync-client", root.dnd ? "-dn" : "-df"])
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label { text: "Focus"; Layout.fillWidth: true }
                                Detail { text: root.dnd ? "Do Not Disturb" : "Off"; Layout.fillWidth: true }
                            }
                        }
                    }

                    RowLayout {
                        spacing: 10
                        Layout.fillWidth: true

                        // Night Light
                        Module {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 74
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Circle {
                                    Layout.alignment: Qt.AlignHCenter
                                    icon: "icons/nightlight.svg"
                                    on: root.nightLight
                                    color: root.nightLight ? Theme.orange : Theme.fgA(0.16)
                                    onClicked: {
                                        root.nightLight = !root.nightLight
                                        root.run([root.home + "/.local/bin/clave-nightlight", root.nightLight ? "on" : "off"])
                                    }
                                }
                                Detail {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Night Light"
                                    color: Theme.fg
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Screen Mirroring
                        Module {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 74
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Circle {
                                    Layout.alignment: Qt.AlignHCenter
                                    icon: "icons/mirroring.svg"
                                    // Every other screen mirrors the built-in one, or
                                    // none does (SHELL-2).
                                    onClicked: Quickshell.execDetached([root.home + "/.local/bin/clave-displays", "mirror", "toggle"])
                                }
                                Detail {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Mirroring"
                                    color: Theme.fg
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            // --- Display ---
            Module {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 7
                    Label { text: "Display" }
                    PillSlider {
                        Layout.fillWidth: true
                        icon: "icons/sun.svg"
                        value: root.brightness
                        onMoved: v => root.setBrightness(v)
                    }
                }
            }

            // --- Sound ---
            Module {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 7
                    Label { text: "Sound" }
                    PillSlider {
                        Layout.fillWidth: true
                        icon: root.sinkReady && (root.sink.audio.muted || root.sink.audio.volume <= 0)
                            ? "icons/speaker-muted.svg" : "icons/speaker.svg"
                        value: root.sinkReady && !root.sink.audio.muted ? root.sink.audio.volume : 0
                        onMoved: v => {
                            if (!root.sinkReady)
                                return
                            root.sink.audio.muted = false
                            root.sink.audio.volume = v
                        }
                    }
                }
            }

            // --- Dark Mode, keyboard brightness ---
            RowLayout {
                spacing: 10
                Layout.fillWidth: true

                Module {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9
                        Circle {
                            icon: "icons/moon.svg"
                            on: !Theme.dark
                            onClicked: ClaveSettings.setAppearance(Theme.dark ? "light" : "dark")
                        }
                        Label { text: Theme.dark ? "Dark Mode" : "Light Mode"; Layout.fillWidth: true }
                    }
                }

                // Only on keyboards with a backlight.
                Module {
                    visible: root.kbdLight !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9
                        Circle {
                            icon: "icons/sun.svg"
                            on: root.kbdOn
                            onClicked: {
                                root.kbdOn = !root.kbdOn
                                root.run(["brightnessctl", "-d", root.kbdLight, "set", root.kbdOn ? "100%" : "0"])
                            }
                        }
                        Label { text: "Keyboard"; Layout.fillWidth: true }
                    }
                }
            }

            // --- Now Playing ---
            Module {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 10

                    ClippingRectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 8
                        color: Theme.fgA(0.12)
                        Image {
                            anchors.fill: parent
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 88
                            sourceSize.height: 88
                        }
                        Image {
                            anchors.centerIn: parent
                            visible: root.artUrl === ""
                            source: "icons/play.svg"
                            width: 16; height: 16
                            sourceSize.width: 32; sourceSize.height: 32
                            opacity: 0.35
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: root.player && root.player.trackTitle ? root.player.trackTitle : "Not Playing"
                        }
                        Detail {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
                        }
                    }

                    Repeater {
                        model: [
                            { "icon": "icons/prev.svg", "act": "prev" },
                            { "icon": root.player && root.player.isPlaying ? "icons/pause.svg" : "icons/play.svg", "act": "toggle" },
                            { "icon": "icons/next.svg", "act": "next" }
                        ]
                        Item {
                            required property var modelData
                            implicitWidth: 26
                            implicitHeight: 26
                            opacity: root.player ? (ctlMouse.containsMouse ? 1 : 0.85) : 0.3
                            Image {
                                anchors.centerIn: parent
                                source: parent.modelData.icon
                                width: parent.modelData.act === "toggle" ? 18 : 17
                                height: width
                                sourceSize.width: width * 2
                                sourceSize.height: height * 2
                            }
                            MouseArea {
                                id: ctlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    const p = root.player
                                    if (!p)
                                        return
                                    const act = parent.modelData.act
                                    if (act === "prev" && p.canGoPrevious) p.previous()
                                    else if (act === "next" && p.canGoNext) p.next()
                                    else if (act === "toggle" && p.canTogglePlaying) p.togglePlaying()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
