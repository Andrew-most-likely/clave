pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Screen recording (SHELL-1): wf-recorder runs only while recording, and the
// menu bar shows a stop button while it does (PERF-3). Screenshot.qml starts
// it; the stop button, the toolbar and `qs ipc call screenshot stop` end it.
Singleton {
    id: root

    readonly property bool recording: proc.running
    property string file: ""
    signal finished(string file)

    // start(ARGS, FILE): ARGS are wf-recorder's source options (-o OUTPUT or
    // -g GEOMETRY), given as a list: nothing goes through a shell.
    function start(args: var, file: string): void {
        if (proc.running)
            return
        root.file = file
        proc.command = ["wf-recorder", ...args, "-f", file]
        proc.running = true
    }
    // wf-recorder finishes the file on SIGINT.
    function stop(): void {
        if (proc.running)
            proc.signal(2)
    }

    Process {
        id: proc
        onExited: (code, status) => root.finished(root.file)
    }
}
