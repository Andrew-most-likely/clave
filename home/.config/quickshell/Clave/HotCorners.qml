import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

// Hot corners: push the pointer into a screen corner to run an action.
// Each corner is a 2×2 px layer surface on every screen. The pointer has to
// rest there briefly, and nothing fires over a full-screen window (games,
// videos).
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // Corner → command, chosen in System Settings > Desktop & Dock > Hot Corners.
    // An empty list turns that corner off.
    readonly property var actions: ({
        "topLeft": ClaveSettings.cornerCommand("topLeft"),
        "topRight": ClaveSettings.cornerCommand("topRight"),
        "bottomLeft": ClaveSettings.cornerCommand("bottomLeft"),
        "bottomRight": ClaveSettings.cornerCommand("bottomRight")
    })

    readonly property int dwell: 120

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Variants {
                model: ["topLeft", "topRight", "bottomLeft", "bottomRight"]

                Scope {
                    id: corner
                    required property string modelData
                    readonly property var command: root.actions[modelData] || []

                    LazyLoader {
                        active: corner.command.length > 0

                        PanelWindow {
                            screen: perScreen.modelData
                            WlrLayershell.layer: WlrLayer.Overlay
                            WlrLayershell.namespace: "clave-hotcorner"
                            exclusionMode: ExclusionMode.Ignore
                            anchors {
                                top: corner.modelData.startsWith("top")
                                bottom: corner.modelData.startsWith("bottom")
                                left: corner.modelData.endsWith("Left")
                                right: corner.modelData.endsWith("Right")
                            }
                            implicitWidth: 2
                            implicitHeight: 2
                            color: "transparent"

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: fire.restart()
                                onExited: fire.stop()
                            }

                            Timer {
                                id: fire
                                interval: root.dwell
                                onTriggered: {
                                    const ws = Hyprland.focusedWorkspace
                                    if (ws && ws.hasFullscreen)
                                        return
                                    Quickshell.execDetached(corner.command)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
