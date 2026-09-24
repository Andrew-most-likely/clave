import Quickshell
import Quickshell.Io
import qs.DockApp

// Owns the dock's lifecycle. The DockWindow — and with it the Wayland layer
// surface, the toplevel tracking and the desktop entry lookups — is created
// only while dock.enabled is true, so a dock turned off in the settings costs
// nothing at startup.
//
// The dock IPC therefore lives here and not in DockWindow: enabling a dock that
// is not loaded has to reach a handler that exists either way. Everything that
// needs the window itself (autohide, reload) goes through DockSettings, which
// the window follows.
Scope {
    id: root

    IpcHandler {
        target: "dock"
        function toggle(): void { DockSettings.setEnabled(!DockSettings.enabled) }
        // Named enable/disable rather than show/hide: "show" is a reserved
        // subcommand of "qs ipc" and would never reach the function.
        function enable(): void { DockSettings.setEnabled(true) }
        function disable(): void { DockSettings.setEnabled(false) }
        function autohideOn(): void { DockSettings.setAutohide(true) }
        function autohideOff(): void { DockSettings.setAutohide(false) }
        function autohideToggle(): void {
            DockSettings.setAutohide(!DockSettings.autohide)
        }
        // Re-read dock.json from disk and apply the changes.
        function reload(): void { DockSettings.reloadSettings() }
    }

    // Instantiates the Minimizer singleton, which listens for the apps'
    // minimize requests, whether or not a dock is loaded.
    readonly property var minimizer: Minimizer

    // Waits for the settings files before building the window, so the dock is
    // created once with the values from disk. See DockSettings.ready.
    // One dock per screen.
    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: loader
            required property var modelData
            active: DockSettings.ready && DockSettings.enabled
            DockWindow { targetScreen: loader.modelData }
        }
    }
}
