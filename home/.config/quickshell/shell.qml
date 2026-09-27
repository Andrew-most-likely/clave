//@ pragma UseQApplication

import Quickshell
import "DockApp"
import "Clave"

ShellRoot {
    // List the IPC targets: qs ipc show

    // One menu bar per screen. Only the first one answers "qs ipc call menubar".
    Variants {
        model: Quickshell.screens
        MenuBar {
            required property var modelData
            screen: modelData
            primary: modelData === Quickshell.screens[0]
        }
    }
    NotificationCenter {}
    Overview {}
    HotCorners {}
    ControlCenter {}
    AboutWindow {}
    SettingsWindow {}
    ActivityMonitor {}
    Screenshot {}
    AppInfo {}
    // Creates the dock window only while the dock is enabled in dock.json.
    DockLoader {}
}