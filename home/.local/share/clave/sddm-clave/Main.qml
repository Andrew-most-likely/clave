// Clave SDDM login window.
// Only uses QtQuick and Qt5Compat.GraphicalEffects, so it runs without any KDE packages.
import QtQuick
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "black"

    // Sizes are designed for 1920x1080 and scale with the screen.
    readonly property real u: Math.min(width / 1920, height / 1080)
    readonly property string textFont: "Inter"
    readonly property string displayFont: "Inter Display"

    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property var now: new Date()

    // Read the selected user and session names out of SDDM's models.
    ListView {
        id: users
        width: 1; height: 1
        opacity: 0
        interactive: false
        model: userModel
        currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
        delegate: Item {
            width: 1; height: 1
            property string loginName: model.name
            property string displayName: model.realName ? model.realName : model.name
            property string picture: model.icon ? model.icon : ""
        }
    }
    ListView {
        id: sessions
        width: 1; height: 1
        opacity: 0
        interactive: false
        model: sessionModel
        currentIndex: root.sessionIndex
        delegate: Item { width: 1; height: 1; property string sessionName: model.name }
    }

    readonly property string userName: users.currentItem ? users.currentItem.loginName : userModel.lastUser
    readonly property string realName: users.currentItem ? users.currentItem.displayName : userName
    readonly property string picture: users.currentItem ? users.currentItem.picture : ""

    function login() {
        if (password.text.length === 0)
            return
        busy.running = true
        sddm.login(root.userName, password.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            busy.running = false
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Image {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.12
    }

    // --- Clock ---
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 60 * root.u
        spacing: -8 * root.u

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: root.displayFont
            font.weight: Font.DemiBold
            font.pixelSize: 28 * root.u
            renderType: Text.QtRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
            color: Qt.rgba(1, 1, 1, 0.9)
            font.family: root.displayFont
            font.weight: Font.Bold
            font.pixelSize: 140 * root.u
            renderType: Text.QtRendering
        }
    }

    // --- User picture, name and password ---
    Column {
        id: userBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 150 * root.u
        spacing: 10 * root.u

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76 * root.u
            height: width

            Rectangle {
                id: avatarFallback
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.25)
                visible: avatar.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: root.realName.length > 0 ? root.realName.charAt(0).toUpperCase() : ""
                    color: "white"
                    font.family: root.displayFont
                    font.weight: Font.Medium
                    font.pixelSize: parent.height * 0.45
                }
            }
            Image {
                id: avatar
                anchors.fill: parent
                source: root.picture
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                visible: false
            }
            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: avatar
                maskSource: avatarMask
                visible: avatar.status === Image.Ready
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.realName
            color: Qt.rgba(1, 1, 1, 0.95)
            font.family: root.textFont
            font.weight: Font.DemiBold
            font.pixelSize: 17 * root.u
        }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200 * root.u
            height: 32 * root.u
            radius: height / 2
            color: Qt.rgba(1, 1, 1, password.activeFocus ? 0.24 : 0.18)

            SequentialAnimation {
                id: shake
                NumberAnimation { target: fieldShift; property: "x"; to: -12 * root.u; duration: 50 }
                NumberAnimation { target: fieldShift; property: "x"; to: 12 * root.u; duration: 70 }
                NumberAnimation { target: fieldShift; property: "x"; to: -8 * root.u; duration: 70 }
                NumberAnimation { target: fieldShift; property: "x"; to: 8 * root.u; duration: 70 }
                NumberAnimation { target: fieldShift; property: "x"; to: 0; duration: 50 }
            }
            transform: Translate { id: fieldShift }

            TextInput {
                id: password
                anchors.fill: parent
                anchors.leftMargin: 14 * root.u
                anchors.rightMargin: 30 * root.u
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignLeft
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "white"
                selectionColor: Qt.rgba(1, 1, 1, 0.35)
                font.family: root.textFont
                font.pixelSize: 13 * root.u
                font.letterSpacing: 1.5 * root.u
                clip: true
                focus: true
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                Keys.onEscapePressed: text = ""

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: root.textFont
                    font.pixelSize: 13 * root.u
                    visible: password.text.length === 0
                }
            }

            Image {
                anchors.right: parent.right
                anchors.rightMargin: 5 * root.u
                anchors.verticalCenter: parent.verticalCenter
                width: 22 * root.u
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: "assets/arrow.svg"
                visible: password.text.length > 0 && !busy.running
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.login()
                }
            }

            // Spinner while SDDM checks the password.
            Item {
                id: busy
                property bool running: false
                anchors.right: parent.right
                anchors.rightMargin: 8 * root.u
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.u
                height: width
                visible: running
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2 * root.u
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                }
                Rectangle {
                    width: 4 * root.u
                    height: width
                    radius: width / 2
                    color: "white"
                    x: parent.width / 2 - width / 2
                    y: -width / 4
                }
                RotationAnimation on rotation {
                    running: busy.running
                    from: 0; to: 360; duration: 900
                    loops: Animation.Infinite
                }
            }
        }
    }

    // --- Sleep, Restart, Shut Down ---
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 * root.u
        spacing: 12 * root.u

        Repeater {
            model: [
                { label: "Sleep", icon: "assets/sleep.svg", allowed: sddm.canSuspend, act: function() { sddm.suspend() } },
                { label: "Restart", icon: "assets/restart.svg", allowed: sddm.canReboot, act: function() { sddm.reboot() } },
                { label: "Shut Down", icon: "assets/shutdown.svg", allowed: sddm.canPowerOff, act: function() { sddm.powerOff() } }
            ]
            // Same width for every button, so the gaps do not depend on the labels.
            delegate: Column {
                visible: modelData.allowed
                width: 72 * root.u
                spacing: 6 * root.u
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40 * root.u
                    height: width
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, powerMouse.pressed ? 0.35 : (powerMouse.containsMouse ? 0.28 : 0.18))
                    Image {
                        anchors.centerIn: parent
                        width: 18 * root.u
                        height: width
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        source: modelData.icon
                    }
                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.act()
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.family: root.textFont
                    font.pixelSize: 12 * root.u
                }
            }
        }
    }

    // --- Session picker (only shown with more than one session) ---
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24 * root.u
        visible: sessionModel.rowCount() > 1
        text: (sessions.currentItem ? sessions.currentItem.sessionName : "") + "  ▾"
        color: Qt.rgba(1, 1, 1, sessionMouse.containsMouse ? 0.95 : 0.7)
        font.family: root.textFont
        font.pixelSize: 12 * root.u
        MouseArea {
            id: sessionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount()
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
