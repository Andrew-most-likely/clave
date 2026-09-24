import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.DockApp

// Full-screen, click-through layer that plays the macOS genie animation: a
// snapshot of the window pours into its dock icon on minimize, and back out of
// it on restore. Mapped only while an animation runs. Hyprland must not animate
// the layer itself (no_anim rule for "macos-genie" in hypr/custom.lua), or the
// snapshot would fade in while the real window has already gone.
PanelWindow {
    id: overlay

    // Icon rectangle (screen coordinates) for a HyprlandToplevel, from the dock.
    property var iconRectFor: ht => Qt.rect(overlay.width / 2 - 16, overlay.height - 50, 32, 32)

    // Hyprland's window rounding (decoration.rounding in hypr/custom.lua): the
    // captured buffer is square, the shader rounds it off.
    readonly property real cornerRadius: 12
    readonly property int duration: 550

    property int running: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "macos-genie"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}
    visible: running > 0

    function minimize(ht: var, address: string): void {
        overlay.start(ht, address, false, "", false)
    }

    function restore(ht: var, address: string, workspace: string, focus: bool): void {
        overlay.start(ht, address, true, workspace, focus)
    }

    function start(ht, address, restoring, workspace, focus): void {
        Minimizer.setBusy(address, true)
        overlay.running++
        genie.createObject(overlay.contentItem, {
            "toplevel": ht, "address": address, "restoring": restoring,
            "workspace": workspace, "focusAfter": focus,
            "iconRect": overlay.iconRectFor(ht)
        })
    }

    Component {
        id: genie

        Item {
            id: anim
            anchors.fill: parent

            property var toplevel: null
            property string address: ""
            property bool restoring: false
            property string workspace: ""
            property bool focusAfter: false
            property rect iconRect
            property rect winRect
            property real progress: restoring ? 1 : 0
            property bool ended: false

            Component.onCompleted: {
                giveUp.start()
                const c = anim.restoring ? Minimizer.rects[anim.address] : undefined
                if (c) {
                    anim.winRect = Qt.rect(c.x, c.y, c.width, c.height)
                    capture.captureSource = anim.toplevel.wayland
                } else {
                    geometry.running = true
                }
            }

            // Where the window is, from Hyprland (layout coordinates, made
            // relative to this screen).
            Process {
                id: geometry
                command: ["hyprctl", "clients", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let clients = []
                        try { clients = JSON.parse(this.text) } catch (e) {}
                        const c = clients.find(c => Minimizer.normalize(c.address) === anim.address)
                        if (!c || !anim.toplevel || !anim.toplevel.wayland) {
                            anim.finish()
                            return
                        }
                        anim.winRect = Qt.rect(c.at[0] - overlay.screen.x, c.at[1] - overlay.screen.y,
                                               c.size[0], c.size[1])
                        capture.captureSource = anim.toplevel.wayland
                    }
                }
            }

            // One still frame of the window. Rendered only through the shader.
            ScreencopyView {
                id: capture
                width: anim.winRect.width
                height: anim.winRect.height
                live: false
                visible: false
                onHasContentChanged: if (hasContent) anim.begin()
            }

            ShaderEffectSource {
                id: snapshot
                sourceItem: capture
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: effect
                anchors.fill: parent
                visible: false
                property var source: snapshot
                property real progress: anim.progress
                property real radius: overlay.cornerRadius
                property rect winRect: anim.winRect
                property rect iconRect: anim.iconRect
                mesh: GridMesh { resolution: Qt.size(4, 64) }
                vertexShader: Qt.resolvedUrl("shaders/genie.vert.qsb")
                fragmentShader: Qt.resolvedUrl("shaders/genie.frag.qsb")
            }

            NumberAnimation {
                id: pour
                target: anim
                property: "progress"
                to: anim.restoring ? 0 : 1
                duration: overlay.duration
                easing.type: Easing.InOutSine
                onFinished: {
                    if (anim.restoring) {
                        // The snapshot stays up, exactly where the window will
                        // be, until Hyprland has the window back on screen.
                        Minimizer.restoreNoAnimation(anim.address, anim.workspace, anim.focusAfter)
                        handOverTimeout.start()
                    } else {
                        anim.finish()
                    }
                }
            }

            // The window changed workspace: it has left (minimize) or is back
            // (restore). Hyprland needs a frame or two to draw that, so the
            // snapshot waits a moment before taking over / letting go.
            Connections {
                target: anim.toplevel
                function onWorkspaceChanged() {
                    const ws = anim.toplevel.workspace
                    const hidden = !!ws && ws.name === "special:minimized"
                    if (!anim.restoring && hidden && anim.moving && !pour.running)
                        settle.start()
                    else if (anim.restoring && !hidden && handOverTimeout.running) {
                        handOverTimeout.stop()
                        settle.start()
                    }
                }
            }

            // true between asking Hyprland to hide the window and the pour.
            property bool moving: false

            // Two frames at 60 Hz: the snapshot is on screen before the window
            // goes, and the window is on screen before the snapshot goes.
            Timer {
                id: settle
                interval: 34
                onTriggered: anim.restoring ? anim.finish() : anim.startPour()
            }

            // Covers the case where the workspace change is never reported.
            Timer {
                id: handOverTimeout
                interval: 300
                onTriggered: anim.restoring ? anim.finish() : anim.startPour()
            }

            // No frame (the capture failed or the window vanished): do the move
            // without the animation.
            Timer {
                id: giveUp
                interval: 400
                onTriggered: if (!effect.visible) anim.finish()
            }

            // Snapshot is up over the (still visible) window; after it has had
            // time to reach the screen, hide the real window underneath it.
            Timer {
                id: coverThenHide
                interval: 34
                onTriggered: {
                    anim.moving = true
                    Minimizer.hideNoAnimation(anim.address)
                    handOverTimeout.start()
                }
            }

            function begin(): void {
                if (anim.ended || effect.visible)
                    return
                effect.visible = true
                if (anim.restoring) {
                    pour.start()
                } else {
                    const r = anim.winRect
                    Minimizer.rects = Object.assign({}, Minimizer.rects, {
                        [anim.address]: { "x": r.x, "y": r.y, "width": r.width, "height": r.height } })
                    coverThenHide.start()
                }
            }

            function startPour(): void {
                if (anim.ended || pour.running || !anim.moving)
                    return
                anim.moving = false
                handOverTimeout.stop()
                pour.start()
            }

            function finish(): void {
                if (anim.ended)
                    return
                anim.ended = true
                // Animation never ran: still carry out the request.
                if (!effect.visible) {
                    if (anim.restoring) {
                        if (anim.focusAfter)
                            Minimizer.moveAndFocus(anim.address, anim.workspace)
                        else
                            Minimizer.moveTo(anim.address, anim.workspace)
                    } else {
                        Minimizer.moveTo(anim.address, "special:minimized")
                    }
                }
                // Hyprland's animations back on for this window, once it is
                // settled back on screen (they stay off while it is hidden).
                if (anim.restoring)
                    Minimizer.noAnimationRestored(anim.address)
                Minimizer.setBusy(anim.address, false)
                overlay.running--
                anim.destroy()
            }
        }
    }
}
