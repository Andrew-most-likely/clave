#!/usr/bin/env python3
"""A desktop test VM for looking at Clave (qemu, no host root).

    tests/vm-desktop.py build        install packages and this checkout (no
                                     hardening), log in automatically
    tests/vm-desktop.py start        boot it (stays running in the background)
    tests/vm-desktop.py run CMD      run CMD as the user inside the Hyprland session
    tests/vm-desktop.py shot NAME    screenshot to ~/.cache/clave-vm/desktop/NAME.png
    tests/vm-desktop.py push         copy this checkout in and run install.sh --update
    tests/vm-desktop.py stop

Uses the files of tests/vm-check (~/.cache/clave-vm: base.qcow2, seed.iso,
key). Software rendering: slow, but enough to check layout and colors
(Phase 6 step 1, APP-3) and that each Clave app opens.
"""
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/.cache/clave-vm")
WORK = os.path.join(CACHE, "desktop")
DISK = os.path.join(WORK, "desktop.qcow2")
PID = os.path.join(WORK, "qemu.pid")
PORT = 2240
SSH = ["ssh", "-i", os.path.join(CACHE, "key"), "-o", "StrictHostKeyChecking=no",
       "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5",
       "-p", str(PORT), "tester@127.0.0.1"]
# The session's environment, found from the running Hyprland.
SESSION = ('export XDG_RUNTIME_DIR=/run/user/$(id -u); '
           'export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -n1); '
           'export WAYLAND_DISPLAY=$(cd $XDG_RUNTIME_DIR && ls wayland-* | grep -v lock | head -n1); '
           'export PATH=$HOME/.local/bin:$PATH; ')


def ssh(cmd, timeout=3600, check=False, stdin=None):
    r = subprocess.run(SSH + [cmd], capture_output=True, text=stdin is None or isinstance(stdin, str),
                       timeout=timeout, input=stdin)
    if check and r.returncode:
        sys.stdout.write((r.stdout or "")[-3000:] + (r.stderr or "")[-3000:])
        raise SystemExit(f"failed: {cmd[:80]}")
    return r


def wait_ssh(timeout=600):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if ssh("true", timeout=15).returncode == 0:
                return True
        except subprocess.TimeoutExpired:
            pass
        time.sleep(3)
    return False


def start(seed=False):
    if os.path.exists(PID):
        try:
            os.kill(int(open(PID).read()), 0)
            return
        except (OSError, ValueError):
            os.unlink(PID)
    cmd = ["qemu-system-x86_64", "-enable-kvm", "-m", "4096", "-smp", "4", "-cpu", "host",
           "-device", "virtio-vga", "-display", "none", "-daemonize", "-pidfile", PID,
           "-nic", f"user,model=virtio-net-pci,hostfwd=tcp::{PORT}-:22",
           "-serial", f"file:{os.path.join(WORK, 'serial.log')}",
           "-drive", f"file={DISK},if=virtio,format=qcow2"]
    if seed:
        cmd += ["-drive", f"file={os.path.join(CACHE, 'seed.iso')},media=cdrom"]
    subprocess.run(cmd, check=True)
    if not wait_ssh():
        raise SystemExit("desktop VM did not come up")


def stop():
    try:
        ssh("sudo systemctl poweroff", timeout=20)
    except subprocess.TimeoutExpired:
        pass
    for _ in range(60):
        if not os.path.exists(PID):
            return
        try:
            os.kill(int(open(PID).read()), 0)
        except (OSError, ValueError):
            return
        time.sleep(1)


def push():
    tar = subprocess.run(["git", "-C", REPO, "archive", "--format=tar", "HEAD"], capture_output=True, check=True).stdout
    # Work-tree changes too, so uncommitted fixes can be looked at.
    diff = subprocess.run(["git", "-C", REPO, "diff", "HEAD", "--binary"], capture_output=True, check=True).stdout
    ssh("rm -rf ~/.local/src/clave && mkdir -p ~/.local/src/clave && tar -x -C ~/.local/src/clave", stdin=tar, check=True)
    if diff.strip():
        ssh("cd ~/.local/src/clave && git apply", stdin=diff, check=True)


def pkgs(group):
    out = []
    for suffix in ("", "-aur"):
        p = os.path.join(REPO, "packages", f"{group}{suffix}.txt")
        if suffix or not os.path.exists(p):
            continue
        for line in open(p):
            line = line.split("#")[0].strip()
            out += line.split()
    return out


def build():
    os.makedirs(WORK, exist_ok=True)
    if os.path.exists(DISK):
        os.unlink(DISK)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "qcow2", "-b",
                    os.path.join(CACHE, "base.qcow2"), DISK, "24G"], check=True)
    start(seed=True)
    print("packages…", flush=True)
    wanted = " ".join(pkgs("core") + pkgs("look") + pkgs("desktop") + pkgs("apps") + ["git", "sddm"])
    ssh(f"sudo pacman -Syu --noconfirm --needed {wanted} >/tmp/pacman.log 2>&1 || tail -20 /tmp/pacman.log", check=True)
    print("clave…", flush=True)
    ssh("git config --global user.email t@t && git config --global user.name t", check=True)
    push()
    ssh("cd ~/.local/src/clave && git init -q && git add -A && git commit -qm vm", check=True)
    ssh("cd ~/.local/src/clave && ./install.sh --no-harden --no-packages --yes >/tmp/install.log 2>&1 || tail -40 /tmp/install.log",
        check=True, timeout=5400)
    ssh("sudo mkdir -p /etc/sddm.conf.d && printf '[Autologin]\\nUser=tester\\nSession=hyprland\\n' "
        "| sudo tee /etc/sddm.conf.d/zz-test-autologin.conf >/dev/null", check=True)
    stop()
    print("built", DISK)


def run(cmd):
    r = ssh(SESSION + cmd, timeout=600)
    sys.stdout.write(r.stdout + r.stderr)
    return r.returncode


def shot(name):
    os.makedirs(WORK, exist_ok=True)
    r = subprocess.run(SSH + [SESSION + "grim -t png -"], capture_output=True, timeout=120)
    if r.returncode or not r.stdout:
        raise SystemExit(r.stderr.decode(errors="replace"))
    path = os.path.join(WORK, name + ".png")
    open(path, "wb").write(r.stdout)
    print(path)


def main():
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    if a[0] == "build":
        build()
    elif a[0] == "start":
        start()
    elif a[0] == "stop":
        stop()
    elif a[0] == "push":
        push()
        sys.exit(run("cd ~/.local/src/clave && git add -A && git commit -qm vm --allow-empty && ./install.sh --update"))
    elif a[0] == "run" and len(a) >= 2:
        sys.exit(run(" ".join(a[1:])))
    elif a[0] == "shot" and len(a) == 2:
        shot(a[1])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
