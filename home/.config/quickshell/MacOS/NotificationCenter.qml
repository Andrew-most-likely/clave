import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// macOS Notification Center widgets: the medium Calendar widget shown at the
// top of the Notification Center. The notifications themselves are swaync's
// control center, pushed down below this card by control-center-margin-top in
// swaync/config.json. This window follows swaync's visibility, so the clock in
// the menu bar only has to toggle swaync.
PanelWindow {
    id: root

    WlrLayershell.namespace: "macos-notification-center"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors { top: true; right: true }
    margins { top: 8; right: 20 }
    implicitWidth: 335
    implicitHeight: 158
    exclusiveZone: 0
    color: "transparent"
    visible: swayncVisible

    readonly property string fontFamily: "SF Pro Text"
    readonly property color red: "#ff453a"

    // --- swaync visibility ---
    property bool swayncVisible: false
    Process {
        id: swayncWatch
        command: ["swaync-client", "-s"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.swayncVisible = JSON.parse(data).visible === true
                } catch (e) {
                    // Ignore malformed lines.
                }
            }
        }
        // swaync restarting ends the subscription; start it again.
        onRunningChanged: if (!running) restartTimer.start()
    }
    Timer { id: restartTimer; interval: 2000; onTriggered: swayncWatch.running = true }

    SystemClock { id: clock; precision: SystemClock.Hours }

    // --- month grid ---
    readonly property date today: clock.date
    readonly property var days: {
        const first = new Date(root.today.getFullYear(), root.today.getMonth(), 1)
        const count = new Date(root.today.getFullYear(), root.today.getMonth() + 1, 0).getDate()
        let cells = []
        for (let i = 0; i < first.getDay(); i++)
            cells.push(0)
        for (let d = 1; d <= count; d++)
            cells.push(d)
        return cells
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.82)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            // Left half: weekday, day number, events.
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 120
                spacing: 0

                Text {
                    text: Qt.formatDate(root.today, "dddd").toUpperCase()
                    color: root.red
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Qt.formatDate(root.today, "d")
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 44
                    font.weight: Font.Normal
                    Layout.topMargin: -4
                }
                Item { Layout.fillHeight: true }
                Text {
                    text: "No events today"
                    color: Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.55)
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }
            }

            // Right half: the month.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                Text {
                    text: Qt.formatDate(root.today, "MMMM").toUpperCase()
                    color: root.red
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                GridLayout {
                    columns: 7
                    columnSpacing: 0
                    rowSpacing: 0
                    Layout.fillWidth: true

                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.55)
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: root.days
                        Item {
                            required property int modelData
                            readonly property bool isToday: modelData === root.today.getDate()
                            Layout.fillWidth: true
                            implicitHeight: 16
                            Rectangle {
                                anchors.centerIn: parent
                                width: 16; height: 16; radius: 8
                                color: root.red
                                visible: parent.isToday
                            }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData > 0 ? parent.modelData : ""
                                color: "#ffffff"
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: parent.isToday ? Font.Bold : Font.Medium
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
