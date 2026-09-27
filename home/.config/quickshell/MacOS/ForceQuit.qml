import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// macOS "Force Quit Applications" (Apple menu, or Super+Alt+Escape).
//   qs ipc call forcequit open
// Lists running apps from `hyprctl clients -j`, one row per app; Force Quit
// sends SIGKILL to every process with a window of that app.
Scope {
    id: root

    property bool open: false
    property var apps: []           // [{ key, name, icon, addresses: [] }]
    property string selected: ""

    IpcHandler {
        target: "forcequit"
        function open(): void {
            root.selected = ""
            root.open = true
            clients.running = false
            clients.running = true
        }
    }

    function entryFor(cls: string): var {
        return DesktopEntries.heuristicLookup(cls)
    }

    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let byKey = ({})
                let order = []
                try {
                    const list = JSON.parse(this.text)
                    for (let i = 0; i < list.length; i++) {
                        const c = list[i]
                        const cls = c.class || c.initialClass || ""
                        // Never list the shell itself: killing it takes down
                        // the menu bar, the dock and this window.
                        if (cls === "" || cls === "org.quickshell" || c.pid <= 0)
                            continue
                        if (byKey[cls] === undefined) {
                            const e = root.entryFor(cls)
                            byKey[cls] = {
                                "key": cls,
                                "name": e && e.name ? e.name : cls,
                                "icon": Quickshell.iconPath(e && e.icon ? e.icon : cls, "application-x-executable"),
                                "addresses": []
                            }
                            order.push(cls)
                        }
                        if (/^0x[0-9a-f]+$/.test(`${c.address}`))
                            byKey[cls].addresses.push(`${c.address}`)
                    }
                } catch (e) {
                    console.warn("forcequit: cannot read hyprctl clients:", e)
                }
                root.apps = order.map(k => byKey[k]).sort((a, b) => a.name.localeCompare(b.name))
            }
        }
    }

    function forceQuit(): void {
        const app = root.apps.find(a => a.key === root.selected)
        if (!app)
            return
        // Hyprland kills the process behind each window it still has, so a PID
        // that was reused since the list was read is never hit.
        for (let i = 0; i < app.addresses.length; i++)
            Quickshell.execDetached(["hyprctl", "dispatch",
                `hl.dsp.window.kill({ window = "address:${app.addresses[i]}" })`])
        root.selected = ""
        refresh.restart()
    }

    Timer { id: refresh; interval: 400; onTriggered: { clients.running = false; clients.running = true } }

    LazyLoader {
        active: root.open

        FloatingWindow {
            title: "Force Quit Applications"
            color: "#1e1e1e"
            implicitWidth: 420
            implicitHeight: 440
            onVisibleChanged: if (!visible) root.open = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "If an app doesn't respond for a while, select its name and click Force Quit."
                    wrapMode: Text.WordWrap
                    color: "#ffffff"
                    font.family: "SF Pro Text"
                    font.pixelSize: 13
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: "#2a2a2c"
                    border.color: Qt.rgba(1, 1, 1, 0.1)
                    clip: true

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 4
                        model: root.apps
                        spacing: 0
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 30
                            radius: 5
                            color: root.selected === modelData.key ? "#0a84ff" : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                spacing: 8
                                Image {
                                    source: modelData.icon
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: "#ffffff"
                                    font.family: "SF Pro Text"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.selected = modelData.key
                                onDoubleClicked: { root.selected = modelData.key; root.forceQuit() }
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "You can open this window by pressing Super-Alt-Escape."
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: "SF Pro Text"
                    font.pixelSize: 11
                }

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 100
                    implicitHeight: 26
                    radius: 6
                    readonly property bool usable: root.selected !== ""
                    color: usable ? (fqMouse.pressed ? "#0063d1" : "#0a84ff") : Qt.rgba(1, 1, 1, 0.12)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "Force Quit"
                        color: parent.usable ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                        font.family: "SF Pro Text"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: fqMouse
                        anchors.fill: parent
                        enabled: parent.usable
                        onClicked: root.forceQuit()
                    }
                }
            }
        }
    }
}
