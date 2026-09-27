//@ pragma UseQApplication
// Calendar (APP-8), its own process:  qs -n -p ~/.config/quickshell/clave-calendar.qml
import Quickshell
import "ClaveApps"

ShellRoot {
    CalendarApp {}
}
