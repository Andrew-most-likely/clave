//@ pragma UseQApplication
// Contacts (APP-8), its own process:  qs -n -p ~/.config/quickshell/clave-contacts.qml
import Quickshell
import "ClaveApps"

ShellRoot {
    ContactsApp {}
}
