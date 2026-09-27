import qs.CustomTheme
import QtQuick

// A toolbar button for the Clave apps (Notes, Calendar, Contacts): text or a
// symbol, with the shell's control colors.
Rectangle {
    id: b
    property string label: ""
    property bool active: false
    property bool enabledState: true
    property bool accent: false
    property string tip: ""
    signal clicked()

    implicitWidth: Math.max(28, t.implicitWidth + 16)
    implicitHeight: 26
    radius: Theme.radiusControl
    color: b.accent ? (m.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent)
         : !b.enabledState ? "transparent"
         : b.active ? Theme.fgA(0.2)
         : m.pressed ? Theme.fgA(0.18) : m.containsMouse ? Theme.fgA(0.1) : "transparent"

    Text {
        id: t
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: b.label
        color: b.accent ? Theme.onAccent : b.enabledState ? Theme.fg : Theme.fgA(0.3)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
    }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabledState
        onClicked: b.clicked()
    }
    Rectangle {
        visible: b.tip !== "" && m.containsMouse
        anchors.top: parent.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: tipText.implicitWidth + 14
        height: 22
        radius: 6
        color: Theme.tooltip
        z: 20
        Text {
            id: tipText
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: b.tip
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
        }
    }
}
