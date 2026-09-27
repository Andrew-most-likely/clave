import qs.CustomTheme
import QtQuick

// A rounded search field with a placeholder, for the Clave apps.
Rectangle {
    id: f
    property alias text: input.text
    property string placeholder: "Search"
    signal accepted()

    implicitWidth: 180
    implicitHeight: 26
    radius: Theme.radiusControl
    color: Theme.fgA(0.08)
    border.color: input.activeFocus ? Theme.accent : "transparent"

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        clip: true
        onAccepted: f.accepted()
        Keys.onEscapePressed: text = ""
    }
    Text {
        textFormat: Text.PlainText
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        text: f.placeholder
        color: Theme.fgA(0.4)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
    }
}
