import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// "About <App>" and "<App> Help" from the menu bar's app menus.
//   qs ipc call appinfo about APP_ID   small About window (name, version, info)
//   qs ipc call appinfo help APP_ID    opens the app's homepage
// Facts come from ~/.local/bin/macos-app-info (pacman or flatpak).
Scope {
    id: root

    property string appId: ""
    property string mode: ""        // "about" or "help"
    property var info: ({})
    property bool aboutOpen: false

    IpcHandler {
        target: "appinfo"
        function about(appId: string): void { root.lookup(appId, "about") }
        function help(appId: string): void { root.lookup(appId, "help") }
    }

    // Homepages come from package metadata; open only web links, never a
    // file:// or other scheme a package could name.
    function webUrl(url: var): string {
        const u = `${url || ""}`
        return /^https?:\/\/[^\s]+$/.test(u) ? u : ""
    }

    function lookup(appId: string, mode: string): void {
        root.appId = appId
        root.mode = mode
        probe.running = false
        probe.running = true
    }

    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/macos-app-info", root.appId]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = {}
                this.text.split("\n").forEach(line => {
                    const i = line.indexOf("=")
                    if (i > 0)
                        out[line.slice(0, i)] = line.slice(i + 1)
                })
                root.info = out
                if (root.mode === "help") {
                    const url = root.webUrl(out.url) || ("https://duckduckgo.com/?q=" + encodeURIComponent((out.name || root.appId) + " help"))
                    Quickshell.execDetached(["xdg-open", url])
                } else {
                    root.aboutOpen = true
                }
            }
        }
    }

    readonly property string iconSource: {
        const entry = DesktopEntries.heuristicLookup(root.appId)
        return Quickshell.iconPath(entry && entry.icon ? entry.icon : root.appId, "application-x-executable")
    }

    LazyLoader {
        active: root.aboutOpen

        FloatingWindow {
            title: "About " + (root.info.name || root.appId)
            color: "#1e1e1e"
            implicitWidth: 300
            implicitHeight: 330
            onVisibleChanged: if (!visible) root.aboutOpen = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 6

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    source: root.iconSource
                    sourceSize.width: 192
                    sourceSize.height: 192
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    text: root.info.name || root.appId
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    visible: (root.info.version || "") !== ""
                    text: "Version " + (root.info.version || "")
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: "SF Pro Text"
                    font.pixelSize: 12
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    text: root.info.description || ""
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.family: "SF Pro Text"
                    font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.webUrl(root.info.url) !== ""
                    text: root.info.url || ""
                    color: "#0a84ff"
                    font.family: "SF Pro Text"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 256
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["xdg-open", root.webUrl(root.info.url)])
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: root.info.source === "flatpak" ? "Installed from Flathub"
                        : root.info.source === "pacman" ? "Installed with pacman" : ""
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.family: "SF Pro Text"
                    font.pixelSize: 11
                }
            }
        }
    }
}
