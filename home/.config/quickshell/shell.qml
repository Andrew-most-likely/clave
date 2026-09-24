//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "WelcomeApp"
import "PowerApp"
import "SidebarApp"
import "CalendarApp"
import "WallpaperApp"
import "StatusbarApp"
import "DockApp"
import "MacOS"
import "CustomTheme"

ShellRoot {
    // Test IPC tools: qs ipc show

    IpcHandler {
        target: "theme-manager" 
        function reload(): void {
            Theme.reloadTheme()
        }
    }

    WelcomeWindow {}
    PowerWindow {}
    SidebarWindow {}
    CalendarWindow {}
    WallpaperWindow {}
    // StatusbarWindow {}  (ML4W bar, replaced by the macOS menu bar)
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
    MissionControl {}
    HotCorners {}
    ControlCenter {}
    AboutWindow {}
    SettingsWindow {}
    ForceQuit {}
    AppInfo {}
    // Creates the dock window only while the dock is enabled in dock.json.
    DockLoader {}
}