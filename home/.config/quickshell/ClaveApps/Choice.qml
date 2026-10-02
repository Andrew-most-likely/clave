import qs.CustomTheme
import QtQuick
import QtQuick.Layouts

// A pop-up choice for the Clave apps: shows the current option, and a list
// under it on click. options: [{ id, label, color? }].
Item {
    id: c
    property var options: []
    property var value
    property bool open: false
    signal picked(var id)

    readonly property var current: c.options.find(o => o.id === c.value) || c.options[0] || { "label": "" }
    implicitWidth: Math.max(120, btnText.implicitWidth + 36)
    implicitHeight: 26
    z: c.open ? 100 : 0

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        color: m.pressed ? Theme.controlPressed : Theme.control
        border.color: Theme.fgA(0.1)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6
            Rectangle {
                visible: !!c.current.color
                implicitWidth: 9; implicitHeight: 9; radius: 5
                color: c.current.color || "transparent"
            }
            Text {
                id: btnText
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: c.current.label
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.px(Theme.fontBody)
            }
            Text { text: "▾"; color: Theme.fgA(0.6); font.pixelSize: Theme.px(11) }
        }
        MouseArea { id: m; anchors.fill: parent; onClicked: c.open = !c.open }
    }

    Rectangle {
        visible: c.open
        anchors.top: parent.bottom
        anchors.topMargin: 4
        width: Math.max(c.width, 160)
        height: list.implicitHeight + 8
        radius: Theme.radiusMenu
        color: Theme.menu
        border.color: Theme.fgA(0.15)
        ColumnLayout {
            id: list
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
            spacing: 0
            Repeater {
                model: c.options
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Theme.menuRowHeight
                    radius: Theme.radiusRow
                    color: om.containsMouse ? Theme.accent : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        spacing: 6
                        Text {
                            text: modelData.id === c.value ? "✓" : ""
                            Layout.preferredWidth: 12
                            color: om.containsMouse ? Theme.onAccent : Theme.fg
                            font.pixelSize: Theme.px(Theme.fontBody)
                        }
                        Rectangle {
                            visible: !!modelData.color
                            implicitWidth: 9; implicitHeight: 9; radius: 5
                            color: modelData.color || "transparent"
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: modelData.label
                            color: om.containsMouse ? Theme.onAccent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.px(Theme.fontBody)
                        }
                    }
                    MouseArea {
                        id: om
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { c.open = false; c.value = modelData.id; c.picked(modelData.id) }
                    }
                }
            }
        }
    }
}
