import Quickshell
import Quickshell.Io
import qs.CustomTheme
import QtQuick
import QtQuick.Layouts

// Activity Monitor (PROJECT_PLAN.md SHELL-3) and the Force Quit dialog.
//   qs ipc call activity open      the window: CPU, Memory, Disk, Network
//   qs ipc call forcequit open     Force Quit Applications (Super+Alt+Escape)
// Engines: ps and free (procps-ng), /proc, and ip (iproute2), all from Arch
// base. They run every 2 seconds only while the window is open, and nothing
// runs while it is closed (PERF-3). Quit sends SIGTERM and Force Quit SIGKILL,
// only to the user's own processes: there is no root helper.
Scope {
    id: root

    // ==========================================
    // FORCE QUIT (small mode)
    // ==========================================
    property bool fqOpen: false
    property var fqApps: []          // [{ key, name, icon, addresses: [] }]
    property string fqSelected: ""

    IpcHandler {
        target: "forcequit"
        function open(): void {
            root.fqSelected = ""
            root.fqOpen = true
            clients.running = false
            clients.running = true
        }
    }

    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let byKey = ({})
                let order = []
                try {
                    const list = JSON.parse(this.text)
                    for (let i = 0; i < list.length; i++) {
                        const c = list[i]
                        const cls = c.class || c.initialClass || ""
                        // Never list the shell itself: killing it takes down
                        // the menu bar, the dock and this window.
                        if (cls === "" || cls === "org.quickshell" || c.pid <= 0)
                            continue
                        if (byKey[cls] === undefined) {
                            const e = DesktopEntries.heuristicLookup(cls)
                            byKey[cls] = {
                                "key": cls,
                                "name": e && e.name ? e.name : cls,
                                "icon": Quickshell.iconPath(e && e.icon ? e.icon : cls, "application-x-executable"),
                                "addresses": []
                            }
                            order.push(cls)
                        }
                        if (/^0x[0-9a-f]+$/.test(`${c.address}`))
                            byKey[cls].addresses.push(`${c.address}`)
                    }
                } catch (e) {
                    console.warn("forcequit: cannot read hyprctl clients:", e)
                }
                root.fqApps = order.map(k => byKey[k]).sort((a, b) => a.name.localeCompare(b.name))
            }
        }
    }

    function forceQuitApp(): void {
        const app = root.fqApps.find(a => a.key === root.fqSelected)
        if (!app)
            return
        // Hyprland kills the process behind each window it still has, so a PID
        // that was reused since the list was read is never hit.
        for (let i = 0; i < app.addresses.length; i++)
            Quickshell.execDetached(["hyprctl", "dispatch",
                `hl.dsp.window.kill({ window = "address:${app.addresses[i]}" })`])
        root.fqSelected = ""
        fqRefresh.restart()
    }

    Timer { id: fqRefresh; interval: 400; onTriggered: { clients.running = false; clients.running = true } }

    // ==========================================
    // ACTIVITY MONITOR (window)
    // ==========================================
    property bool open: false
    property string tab: "cpu"             // cpu, memory, disk, network
    property string filter: ""
    property bool allProcesses: false
    property string sortKey: "cpu"
    property bool sortDesc: true
    property int selectedPid: -1
    property int myUid: -1

    property var procs: []                 // [{ pid, uid, user, name, cpu, time, mem, read, written }]
    property var ifaces: []                // [{ name, rx, tx, rxRate, txRate, rxPackets, txPackets }]
    property var summary: ({})
    property var prev: null                // counters from the last sample

    IpcHandler {
        target: "activity"
        function open(): void {
            root.open = true
            sample.running = false
            sample.running = true
        }
        function close(): void { root.open = false }
    }

    readonly property var tabs: [
        { "id": "cpu", "label": "CPU" }, { "id": "memory", "label": "Memory" },
        { "id": "disk", "label": "Disk" }, { "id": "network", "label": "Network" }
    ]
    readonly property var columns: ({
        "cpu":     [{ "key": "name", "label": "Process Name", "w": 0 }, { "key": "cpu", "label": "% CPU", "w": 70 },
                    { "key": "time", "label": "CPU Time", "w": 90 }, { "key": "pid", "label": "PID", "w": 70 },
                    { "key": "user", "label": "User", "w": 100 }],
        "memory":  [{ "key": "name", "label": "Process Name", "w": 0 }, { "key": "mem", "label": "Memory", "w": 100 },
                    { "key": "pid", "label": "PID", "w": 70 }, { "key": "user", "label": "User", "w": 100 }],
        "disk":    [{ "key": "name", "label": "Process Name", "w": 0 }, { "key": "written", "label": "Bytes Written", "w": 110 },
                    { "key": "read", "label": "Bytes Read", "w": 110 }, { "key": "pid", "label": "PID", "w": 70 },
                    { "key": "user", "label": "User", "w": 100 }],
        "network": [{ "key": "name", "label": "Interface", "w": 0 }, { "key": "rx", "label": "Received", "w": 110 },
                    { "key": "tx", "label": "Sent", "w": 110 }, { "key": "rxRate", "label": "Rcvd/s", "w": 100 },
                    { "key": "txRate", "label": "Sent/s", "w": 100 }]
    })

    function setTab(id: string): void {
        root.tab = id
        root.sortKey = ({ "cpu": "cpu", "memory": "mem", "disk": "written", "network": "rx" })[id]
        root.sortDesc = true
    }

    // One read of everything the tabs show. A fixed script: nothing from the
    // user or from other processes goes into it.
    Process {
        id: sample
        command: ["sh", "-c",
            "echo '#me'; id -u;" +
            " echo '#uptime'; cat /proc/uptime;" +
            " echo '#cpu'; head -n1 /proc/stat;" +
            " echo '#ps'; ps -eo pid=,uid=,user:32=,args=;" +
            " echo '#stat'; cat /proc/[0-9]*/stat 2>/dev/null;" +
            " echo '#io'; grep -H -E '^(read|write)_bytes' /proc/[0-9]*/io 2>/dev/null;" +
            " echo '#mem'; free -b;" +
            " echo '#disk'; cat /proc/diskstats;" +
            " echo '#net'; ip -s -j link"]
        stdout: StdioCollector { onStreamFinished: root.parse(this.text) }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.open
        onTriggered: { sample.running = false; sample.running = true }
    }

    function parse(text: string): void {
        let sec = {}
        let cur = ""
        text.split("\n").forEach(l => {
            if (l.startsWith("#") && /^#[a-z]+$/.test(l)) { cur = l.slice(1); sec[cur] = []; return }
            if (cur !== "" && l !== "") sec[cur].push(l)
        })
        const uptime = parseFloat((sec.uptime || ["0"])[0])
        root.myUid = parseInt((sec.me || ["-1"])[0])
        const hz = 100      // USER_HZ on Linux
        const page = 4096

        let users = {}
        ;(sec.ps || []).forEach(l => {
            const f = l.trim().split(/\s+/)
            // The kernel cuts names at 15 characters; the program's file
            // name from the command line is the full one.
            users[f[0]] = { "uid": parseInt(f[1]), "user": f[2], "exe": (f[3] || "").split("/").pop() }
        })
        let io = {}
        ;(sec.io || []).forEach(l => {
            const m = l.match(/^\/proc\/(\d+)\/io:(read|write)_bytes: (\d+)/)
            if (m) { io[m[1]] = io[m[1]] || {}; io[m[1]][m[2]] = parseInt(m[3]) }
        })

        const last = root.prev
        const dt = last ? Math.max(0.1, uptime - last.uptime) : 0
        let ticks = {}
        let list = []
        ;(sec.stat || []).forEach(l => {
            const a = l.indexOf("("), b = l.lastIndexOf(")")
            if (a < 0 || b < 0) return
            const pid = l.slice(0, a).trim()
            const f = l.slice(b + 2).split(" ")      // f[0] is field 3 (state)
            const t = parseInt(f[11]) + parseInt(f[12])   // utime + stime
            ticks[pid] = t
            const u = users[pid]
            if (!u) return
            if (!root.allProcesses && u.uid !== root.myUid) return
            const before = last ? last.ticks[pid] : undefined
            let name = l.slice(a + 1, b)
            if (name.length === 15 && u.exe.startsWith(name)) name = u.exe
            list.push({
                "pid": parseInt(pid), "uid": u.uid, "user": u.user, "name": name,
                "cpu": before !== undefined && dt > 0 ? (t - before) / hz / dt * 100 : 0,
                "time": t / hz, "mem": parseInt(f[21]) * page,
                "read": (io[pid] || {}).read || 0, "written": (io[pid] || {}).write || 0
            })
        })

        // CPU load: /proc/stat's first line, as a share of all cores.
        const c = ((sec.cpu || [""])[0]).trim().split(/\s+/).slice(1).map(Number)
        const cpu = { "user": c[0] + c[1], "system": c[2] + c[5] + c[6], "idle": c[3] + c[4] }
        let s = {}
        if (last && last.cpu) {
            const du = cpu.user - last.cpu.user, ds = cpu.system - last.cpu.system, di = cpu.idle - last.cpu.idle
            const tot = Math.max(1, du + ds + di)
            s.cpuUser = du / tot * 100; s.cpuSystem = ds / tot * 100; s.cpuIdle = di / tot * 100
        }
        s.threads = list.length

        // Memory: free -b
        ;(sec.mem || []).forEach(l => {
            const f = l.trim().split(/\s+/)
            if (f[0] === "Mem:") { s.memTotal = +f[1]; s.memUsed = +f[2]; s.memCached = +f[5]; s.memAvail = +f[6] }
            if (f[0] === "Swap:") { s.swapTotal = +f[1]; s.swapUsed = +f[2] }
        })

        // Disk: whole disks only, sectors of 512 bytes.
        let disk = { "read": 0, "written": 0, "reads": 0, "writes": 0 }
        ;(sec.disk || []).forEach(l => {
            const f = l.trim().split(/\s+/)
            if (!/^(sd[a-z]+|vd[a-z]+|nvme\d+n\d+|mmcblk\d+)$/.test(f[2])) return
            disk.reads += +f[3]; disk.read += +f[5] * 512; disk.writes += +f[7]; disk.written += +f[9] * 512
        })
        if (last && last.disk && dt > 0) {
            s.diskReadRate = (disk.read - last.disk.read) / dt
            s.diskWriteRate = (disk.written - last.disk.written) / dt
            s.diskReadsRate = (disk.reads - last.disk.reads) / dt
            s.diskWritesRate = (disk.writes - last.disk.writes) / dt
        }
        s.diskRead = disk.read; s.diskWritten = disk.written

        // Network: ip -s -j link, loopback left out.
        let nets = []
        let net = { "rx": 0, "tx": 0 }
        try {
            JSON.parse((sec.net || ["[]"]).join("\n")).forEach(n => {
                if (n.link_type === "loopback" || !n.stats64) return
                const rx = n.stats64.rx.bytes, tx = n.stats64.tx.bytes
                const lp = last && last.nets ? last.nets[n.ifname] : undefined
                nets.push({ "name": n.ifname, "rx": rx, "tx": tx,
                            "rxRate": lp && dt > 0 ? (rx - lp.rx) / dt : 0,
                            "txRate": lp && dt > 0 ? (tx - lp.tx) / dt : 0,
                            "rxPackets": n.stats64.rx.packets, "txPackets": n.stats64.tx.packets })
                net.rx += rx; net.tx += tx
            })
        } catch (e) {
            console.warn("activity: cannot read ip -s -j link:", e)
        }
        if (last && last.net && dt > 0) {
            s.netRxRate = (net.rx - last.net.rx) / dt
            s.netTxRate = (net.tx - last.net.tx) / dt
        }
        s.netRx = net.rx; s.netTx = net.tx

        let byName = {}
        nets.forEach(n => byName[n.name] = n)
        root.prev = { "uptime": uptime, "ticks": ticks, "cpu": cpu, "disk": disk, "net": net, "nets": byName }
        root.procs = list
        root.ifaces = nets
        root.summary = s
    }

    readonly property var rows: {
        const src = root.tab === "network" ? root.ifaces : root.procs
        const q = root.filter.toLowerCase()
        const k = root.sortKey, d = root.sortDesc ? -1 : 1
        return src.filter(r => q === "" || `${r.name}`.toLowerCase().indexOf(q) >= 0 || `${r.pid}` === q)
            .slice().sort((a, b) => {
                const x = a[k], y = b[k]
                return (typeof x === "string" ? x.localeCompare(y) : x - y) * d
            })
    }
    readonly property var selectedProc: root.procs.find(p => p.pid === root.selectedPid)
    readonly property bool canQuit: root.tab !== "network" && !!root.selectedProc
                                    && root.selectedProc.uid === root.myUid

    function quit(force: bool): void {
        const p = root.selectedProc
        if (!p || p.uid !== root.myUid)
            return
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM", `${p.pid}`])
        root.selectedPid = -1
    }

    function bytes(n: real): string {
        if (!(n >= 0)) return "–"
        const u = ["bytes", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1000 && i < u.length - 1) { n /= 1000; i++ }
        return (i === 0 ? n.toFixed(0) : n.toFixed(n < 10 ? 2 : 1)) + " " + u[i]
    }
    function duration(s: real): string {
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
        return (h > 0 ? h + ":" + `${m}`.padStart(2, "0") : `${m}`) + ":" + r.toFixed(2).padStart(5, "0")
    }
    function cell(r: var, key: string): string {
        const v = r[key]
        if (key === "cpu") return v.toFixed(1)
        if (key === "time") return root.duration(v)
        if (["mem", "read", "written", "rx", "tx"].includes(key)) return root.bytes(v)
        if (key === "rxRate" || key === "txRate") return root.bytes(v) + "/s"
        return `${v}`
    }
    readonly property var footer: {
        const s = root.summary
        const pct = v => v === undefined ? "…" : v.toFixed(1) + "%"
        const rate = v => v === undefined ? "…" : root.bytes(v) + "/s"
        if (root.tab === "cpu") return [["System", pct(s.cpuSystem)], ["User", pct(s.cpuUser)], ["Idle", pct(s.cpuIdle)],
                                        ["Processes", `${s.threads || 0}`]]
        if (root.tab === "memory") return [["Physical Memory", root.bytes(s.memTotal)], ["Memory Used", root.bytes(s.memUsed)],
                                           ["Cached Files", root.bytes(s.memCached)],
                                           ["Swap Used", s.swapTotal ? root.bytes(s.swapUsed) : "No swap"]]
        if (root.tab === "disk") return [["Reads in", root.bytes(s.diskRead)], ["Writes out", root.bytes(s.diskWritten)],
                                         ["Data read/sec", rate(s.diskReadRate)], ["Data written/sec", rate(s.diskWriteRate)]]
        return [["Data received", root.bytes(s.netRx)], ["Data sent", root.bytes(s.netTx)],
                ["Data received/sec", rate(s.netRxRate)], ["Data sent/sec", rate(s.netTxRate)]]
    }

    component ToolButton: Rectangle {
        id: tb
        property string label
        property bool enabledState: true
        signal clicked()
        implicitWidth: tbText.implicitWidth + 20
        implicitHeight: 26
        radius: Theme.radiusControl
        color: !enabledState ? Theme.fgA(0.05) : tbMouse.pressed ? Theme.controlPressed : Theme.control
        Text {
            id: tbText
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: tb.label
            color: tb.enabledState ? Theme.fg : Theme.fgA(0.35)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
        }
        MouseArea {
            id: tbMouse
            anchors.fill: parent
            enabled: tb.enabledState
            onClicked: tb.clicked()
        }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            title: "Activity Monitor"
            color: Theme.window
            implicitWidth: 900
            implicitHeight: 600
            onVisibleChanged: if (!visible) { root.open = false; root.prev = null }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Toolbar: quit buttons, tabs, search.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ToolButton {
                        label: "Quit"
                        enabledState: root.canQuit
                        onClicked: root.quit(false)
                    }
                    ToolButton {
                        label: "Force Quit"
                        enabledState: root.canQuit
                        onClicked: root.quit(true)
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        implicitWidth: tabRow.implicitWidth + 4
                        implicitHeight: 26
                        radius: Theme.radiusControl
                        color: Theme.fgA(0.08)
                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: root.tabs
                                Rectangle {
                                    required property var modelData
                                    width: tabLabel.implicitWidth + 24
                                    height: 22
                                    radius: Theme.radiusControl - 1
                                    color: root.tab === modelData.id ? Theme.control : "transparent"
                                    Text {
                                        id: tabLabel
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontBody
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTab(modelData.id) }
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    ToolButton {
                        visible: root.tab !== "network"
                        label: root.allProcesses ? "All Processes" : "My Processes"
                        onClicked: root.allProcesses = !root.allProcesses
                    }
                    Rectangle {
                        implicitWidth: 180
                        implicitHeight: 26
                        radius: Theme.radiusControl
                        color: Theme.fgA(0.08)
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            clip: true
                            onTextChanged: root.filter = text
                        }
                        Text {
                            textFormat: Text.PlainText
                            anchors.fill: search
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text === ""
                            text: "Search"
                            color: Theme.fgA(0.4)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                        }
                    }
                }

                // Table
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusControl
                    color: Theme.group
                    border.color: Theme.fgA(0.1)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            // A nested layout fills by default; the list gets the height.
                            Layout.fillHeight: false
                            Layout.preferredHeight: 26
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            spacing: 0
                            Repeater {
                                model: root.columns[root.tab]
                                Item {
                                    required property var modelData
                                    Layout.fillWidth: modelData.w === 0
                                    Layout.preferredWidth: modelData.w
                                    Layout.fillHeight: true
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: modelData.w === 0 ? Text.AlignLeft : Text.AlignRight
                                        text: modelData.label + (root.sortKey === modelData.key ? (root.sortDesc ? " ▾" : " ▴") : "")
                                        color: Theme.fgA(0.6)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSecondary
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.sortKey === modelData.key) root.sortDesc = !root.sortDesc
                                            else { root.sortKey = modelData.key; root.sortDesc = modelData.key !== "name" && modelData.key !== "user" }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.fgA(0.1) }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: root.rows
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 22
                                readonly property bool sel: root.tab !== "network" && modelData.pid === root.selectedPid
                                color: sel ? Theme.accent : index % 2 ? Theme.fgA(0.03) : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 0
                                    Repeater {
                                        model: root.columns[root.tab]
                                        Text {
                                            required property var modelData
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: modelData.w === 0
                                            Layout.preferredWidth: modelData.w
                                            horizontalAlignment: modelData.w === 0 ? Text.AlignLeft : Text.AlignRight
                                            text: root.cell(row.modelData, modelData.key)
                                            color: row.sel ? Theme.onAccent : Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontBody - 1
                                            font.features: { "tnum": 1 }
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (root.tab !== "network") root.selectedPid = row.modelData.pid
                                }
                            }
                        }
                    }
                }

                // Summary under the table, per tab.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: Theme.radiusControl
                    color: Theme.group
                    border.color: Theme.fgA(0.1)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 24
                        Repeater {
                            model: root.footer
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    textFormat: Text.PlainText
                                    text: modelData[0]
                                    color: Theme.fgA(0.6)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: modelData[1]
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontTitle
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // FORCE QUIT WINDOW
    // ==========================================
    LazyLoader {
        active: root.fqOpen

        FloatingWindow {
            title: "Force Quit Applications"
            color: Theme.window
            implicitWidth: 420
            implicitHeight: 440
            onVisibleChanged: if (!visible) root.fqOpen = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "If an app doesn't respond for a while, select its name and click Force Quit."
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.family: "Inter"
                    font.pixelSize: 13
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: Theme.group
                    border.color: Theme.fgA(0.1)
                    clip: true

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 4
                        model: root.fqApps
                        spacing: 0
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 30
                            radius: Theme.radiusRow
                            color: root.fqSelected === modelData.key ? Theme.accent : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                spacing: 8
                                Image {
                                    source: modelData.icon
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.fg
                                    font.family: "Inter"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.fqSelected = modelData.key
                                onDoubleClicked: { root.fqSelected = modelData.key; root.forceQuitApp() }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: "You can open this window by pressing Super-Alt-Escape."
                        color: Theme.fgA(0.5)
                        font.family: "Inter"
                        font.pixelSize: 11
                    }
                    ToolButton {
                        label: "Activity Monitor…"
                        onClicked: { root.fqOpen = false; root.open = true; sample.running = false; sample.running = true }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 100
                    implicitHeight: 26
                    radius: 6
                    readonly property bool usable: root.fqSelected !== ""
                    color: usable ? (fqMouse.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent) : Theme.fgA(0.12)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "Force Quit"
                        color: parent.usable ? Theme.onAccent : Theme.fgA(0.4)
                        font.family: "Inter"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: fqMouse
                        anchors.fill: parent
                        enabled: parent.usable
                        onClicked: root.forceQuitApp()
                    }
                }
            }
        }
    }
}
