import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// "About This Mac" window. Toggled with: qs ipc call about toggle
Scope {
    id: root

    property bool open: false
    property var info: ({})

    IpcHandler {
        target: "about"
        function toggle(): void { root.open = !root.open }
    }

    // Collects hardware facts as key=value lines.
    Process {
        id: probe
        running: root.open
        command: ["bash", "-c",
            "echo \"host=$(cat /etc/hostname 2>/dev/null || uname -n)\";" +
            "echo \"os=$(. /etc/os-release; echo $PRETTY_NAME)\";" +
            "echo \"kernel=$(uname -r)\";" +
            "echo \"chip=$(lscpu | sed -n 's/^Model name: *//p' | head -1)\";" +
            "echo \"memory=$(free -g --si | awk '/^Mem:/{print $2}') GB\";" +
            "echo \"gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | sed 's/.*: //')\";" +
            "echo \"display=$(hyprctl monitors | awk '/@/{split($1,a,\"@\"); printf \"%s @ %dHz\", a[1], a[2]; exit}')\";" +
            "echo \"model=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = {}
                this.text.split("\n").forEach(line => {
                    const i = line.indexOf("=")
                    if (i > 0)
                        out[line.slice(0, i)] = line.slice(i + 1)
                })
                root.info = out
            }
        }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            title: "About This Mac"
            color: "#1e1e1e"
            implicitWidth: 300
            implicitHeight: 460
            onVisibleChanged: if (!visible) root.open = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 6

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    source: "icons/apple.svg"
                    sourceSize.width: 160
                    sourceSize.height: 196
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 98
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 14
                    text: root.info.model || "MacBook Pro"
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: root.info.host || ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: "SF Pro Text"
                    font.pixelSize: 12
                }

                Item { Layout.preferredHeight: 14 }

                Repeater {
                    model: [
                        ["Chip", root.info.chip],
                        ["Memory", root.info.memory],
                        ["Graphics", root.info.gpu],
                        ["Display", root.info.display],
                        ["OS", root.info.os],
                        ["Kernel", root.info.kernel]
                    ]
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            textFormat: Text.PlainText
                            text: modelData[0]
                            color: "#ffffff"
                            font.family: "SF Pro Text"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.preferredWidth: 70
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData[1] || "…"
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.family: "SF Pro Text"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 120
                    implicitHeight: 24
                    radius: 6
                    color: moreMouse.pressed ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.18)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "More Info…"
                        color: "#ffffff"
                        font.family: "SF Pro Text"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: moreMouse
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["kitty", "--class", "dotfiles-floating", "-e", "bash", "-c", "fastfetch; read -n1"])
                    }
                }
            }
        }
    }
}
