pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Clave

// Minimize and restore with the genie animation.
//
// Hyprland has no minimized state, so a minimized window waits on
// special:minimized (the menu bar, the dock and "Show All" all use it). Apps ask
// to be minimized with the yellow title bar button; Hyprland ignores that on its
// own, and the hypr-minimize plugin (~/.local/share/clave/hypr-minimize,
// loaded in hypr/custom.lua) forwards it as the IPC event
// "minimized>>ADDRESS,1", handled below.
//
// The dock on the window's screen claims each request and plays the animation
// (see GenieOverlay). A request nobody claims — the dock is off — just moves the
// window without one. DockLoader references this singleton so the IPC listener
// exists even while the dock is disabled.
Singleton {
    id: root

    // Emitted with the HyprlandToplevel about to be minimized / restored. A
    // handler that takes it calls claim() before returning.
    signal minimizeRequested(var toplevel, string address)
    signal restoreRequested(var toplevel, string address, string workspace, bool focus)

    property bool claimed: false
    function claim(): void { root.claimed = true }

    // Addresses with an animation running, so a second click on the button (or
    // the dock icon) does not start another one.
    property var busy: ({})
    function setBusy(address: string, on: bool): void {
        let b = Object.assign({}, root.busy)
        if (on)
            b[address] = true
        else
            delete b[address]
        root.busy = b
    }

    // Last on-screen geometry of each minimized window, by address, so the
    // restore animation can grow back to where the window was.
    property var rects: ({})

    // Hyprland window address with the 0x prefix, or "".
    function normalize(address: string): string {
        const a = `${address ?? ""}`
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a)
    }

    function find(address: string): var {
        const a = root.normalize(address)
        const list = Hyprland.toplevels.values
        for (let i = 0; i < list.length; i++)
            if (root.normalize(`${list[i].address}`) === a)
                return list[i]
        return null
    }

    function isMinimized(ht: var): bool {
        return ht && ht.workspace !== null && ht.workspace.name === "special:minimized"
    }

    function hypr(lua: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", lua])
    }

    function moveTo(address: string, workspace: string): void {
        root.hypr(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "address:${address}" })`)
    }

    function focus(address: string): void {
        root.hypr(`hl.dsp.focus({ window = "address:${address}" })`)
    }

    // Runs Lua dispatches one after another, in one shell. As separate
    // hyprctl processes they could land out of order (a focus before the move
    // leaves the restored window unfocused).
    function dispatchInOrder(luas: var): void {
        const script = luas.map((_, i) => `hyprctl dispatch "$${i + 1}"`).join(" && ")
        Quickshell.execDetached(["sh", "-c", script, "sh"].concat(luas))
    }

    function noAnim(address: string, on: bool): string {
        return `hl.dsp.window.set_prop({ prop = "no_anim", value = "${on ? "1" : "unset"}", window = "address:${address}" })`
    }

    function moveLua(address: string, workspace: string): string {
        return `hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "address:${address}" })`
    }

    // Moves a window back and focuses it.
    function moveAndFocus(address: string, workspace: string): void {
        root.dispatchInOrder([root.moveLua(address, workspace),
            `hl.dsp.focus({ window = "address:${address}" })`])
    }

    // For the genie: the window leaves and returns without Hyprland's own
    // animation, so it swaps with the snapshot in a single frame.
    // noAnimationRestored() puts the animations back afterwards.
    function hideNoAnimation(address: string): void {
        root.dispatchInOrder([root.noAnim(address, true), root.moveLua(address, "special:minimized")])
    }

    function restoreNoAnimation(address: string, workspace: string, focus: bool): void {
        let luas = [root.noAnim(address, true), root.moveLua(address, workspace)]
        if (focus)
            luas.push(`hl.dsp.focus({ window = "address:${address}" })`)
        root.dispatchInOrder(luas)
    }

    function noAnimationRestored(address: string): void {
        root.hypr(root.noAnim(address, false))
    }

    function minimize(address: string): void {
        const a = root.normalize(address)
        const ht = root.find(a)
        if (!ht || root.isMinimized(ht) || root.busy[a])
            return
        // System Settings > Desktop & Dock > "Minimize windows using": Genie
        // plays the dock animation, Scale leaves it to Hyprland's own.
        root.claimed = false
        if (ClaveSettings.get("windows", "minimizeEffect") === "genie")
            root.minimizeRequested(ht, a)
        if (!root.claimed)
            root.moveTo(a, "special:minimized")
    }

    // Brings a minimized window back onto `workspace` (a workspace id), focusing
    // it when `focus` is set.
    function restore(address: string, workspace: string, focus: bool): void {
        const a = root.normalize(address)
        const ht = root.find(a)
        if (!ht || root.busy[a])
            return
        root.claimed = false
        if (ClaveSettings.get("windows", "minimizeEffect") === "genie")
            root.restoreRequested(ht, a, workspace, focus)
        if (!root.claimed) {
            if (focus)
                root.moveAndFocus(a, workspace)
            else
                root.moveTo(a, workspace)
        }
    }

    // qs ipc call minimize active          — minimize the focused window
    // qs ipc call minimize restore ADDRESS — bring one back to this workspace
    IpcHandler {
        target: "minimize"
        function active(): void {
            const ht = Hyprland.activeToplevel
            if (ht)
                root.minimize(`${ht.address}`)
        }
        function restore(address: string): void {
            const ws = Hyprland.focusedWorkspace
            if (ws)
                root.restore(address, `${ws.id}`, true)
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "minimized")
                return
            const parts = `${event.data}`.split(",")
            if (parts.length === 2 && parts[1] === "1")
                root.minimize(parts[0])
        }
    }
}
