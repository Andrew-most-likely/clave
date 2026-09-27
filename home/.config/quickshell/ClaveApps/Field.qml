import qs.CustomTheme
import QtQuick

// A one-line text field for the Clave apps. `valid` turns the border red.
Rectangle {
    id: f
    property alias text: input.text
    property string placeholder: ""
    property bool valid: true
    property alias input: input
    property int pixelSize: Theme.fontBody
    property bool multiline: false
    signal edited()

    implicitWidth: 200
    implicitHeight: f.multiline ? 70 : 26
    radius: Theme.radiusControl
    color: Theme.fgA(0.06)
    border.color: !f.valid ? Theme.red : input.activeFocus ? Theme.accent : Theme.fgA(0.12)

    TextEdit {
        id: input
        anchors.fill: parent
        anchors.margins: 6
        anchors.topMargin: f.multiline ? 6 : 0
        anchors.bottomMargin: f.multiline ? 6 : 0
        verticalAlignment: f.multiline ? TextEdit.AlignTop : TextEdit.AlignVCenter
        wrapMode: f.multiline ? TextEdit.Wrap : TextEdit.NoWrap
        textFormat: TextEdit.PlainText
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.fontFamily
        font.pixelSize: f.pixelSize
        clip: true
        selectByMouse: true
        onTextChanged: f.edited()
        Keys.onReturnPressed: event => { if (f.multiline) event.accepted = false; else event.accepted = true }
        Keys.onTabPressed: event => { nextItemInFocusChain().forceActiveFocus(); event.accepted = true }
    }
    Text {
        textFormat: Text.PlainText
        anchors.fill: input
        verticalAlignment: input.verticalAlignment
        visible: input.text === "" && !input.activeFocus
        text: f.placeholder
        color: Theme.fgA(0.35)
        font.family: Theme.fontFamily
        font.pixelSize: f.pixelSize
    }
}
