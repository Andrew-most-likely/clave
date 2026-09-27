#!/usr/bin/env python3
"""End-to-end test of Disk Encryption in place (SEC-5) in qemu, no host root.

    tests/vm-encrypt.py build [grub|sdboot|limine ...]   build the test systems
    tests/vm-encrypt.py run   [grub|sdboot|limine|interrupted ...]

Uses the files of tests/vm-check (in ~/.cache/clave-vm): base.qcow2 (the Arch
cloud image), seed.iso (cloud-init with user "tester" and the SSH key "key").
The cloud image is the builder: it pacstraps each test system onto a second
disk (tests/vm-encrypt-build.sh) and later stands in for the Arch live USB in
the offline stage. Each run:

  1. boots the test system (UEFI), runs the checks and `clave-encrypt prepare`
     and picks "Clave (encrypted)" for the next boot;
  2. boots the builder with the test disk attached and runs the offline
     script under expect (passphrase, recovery key);
     "interrupted" kills the VM during reencrypt, then runs it again to resume;
  3. boots "Clave (encrypted)", types the passphrase on the serial console,
     checks that the status is On and runs `clave-encrypt finish`;
  4. boots the normal entry, unlocks with the recovery key this time, and
     checks the status again.
Prints one "VMENC:" line per step; exits 1 when one fails.
"""
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/.cache/clave-vm")
WORK = os.path.join(CACHE, "encrypt")
KEY = os.path.join(CACHE, "key")
OVMF_CODE = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
PASSPHRASE = "clave test passphrase 1"
VARIANTS = ["grub", "sdboot", "limine"]
SSH = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
       "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5"]
failed = []


def say(msg):
    print(f"VMENC: {msg}", flush=True)


def check(ok, what):
    say(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failed.append(what)
    return ok


class VM:
    """One qemu process with SSH on a forwarded port and the serial console
    on a Unix socket, logged to a file and watched for passphrase prompts."""

    def __init__(self, name, disks, port, uefi_vars=None, seed=False, throttle=None):
        self.name, self.port = name, port
        self.log = open(os.path.join(WORK, f"{name}.serial.log"), "ab")
        self.sock_path = os.path.join(WORK, f"{name}.sock")
        self.answer = None          # text typed at the next passphrase prompt
        self.prompts = 0
        cmd = ["qemu-system-x86_64", "-enable-kvm", "-m", "2048", "-smp", "2", "-cpu", "host",
               "-display", "none", "-no-reboot",
               "-nic", f"user,model=virtio-net-pci,hostfwd=tcp::{port}-:22",
               "-chardev", f"socket,id=s0,path={self.sock_path},server=on,wait=off",
               "-serial", "chardev:s0"]
        if uefi_vars:
            cmd += ["-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
                    "-drive", f"if=pflash,format=raw,file={uefi_vars}"]
        for i, d in enumerate(disks):
            opts = f"file={d},if=virtio,format=qcow2"
            if throttle and i == len(disks) - 1:
                opts += f",throttling.bps-total={throttle}"
            cmd += ["-drive", opts]
        if seed:
            cmd += ["-drive", f"file={os.path.join(CACHE, 'seed.iso')},media=cdrom"]
        if os.path.exists(self.sock_path):
            os.unlink(self.sock_path)
        self.proc = subprocess.Popen(cmd)
        for _ in range(100):
            if os.path.exists(self.sock_path):
                break
            time.sleep(0.1)
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(self.sock_path)
        threading.Thread(target=self._serial, daemon=True).start()

    def _serial(self):
        buf = b""
        while True:
            try:
                data = self.sock.recv(4096)
            except OSError:
                return
            if not data:
                return
            self.log.write(data)
            self.log.flush()
            buf = (buf + data)[-400:]
            if self.answer and re.search(rb"(?i)(passphrase|password)[^\n]*$", buf):
                time.sleep(1)
                self.sock.sendall(self.answer.encode() + b"\r")
                self.prompts += 1
                buf = b""

    def ssh(self, command, user="tester", timeout=900, stdin=None):
        return subprocess.run(SSH + ["-p", str(self.port), f"{user}@127.0.0.1", command],
                              input=stdin, capture_output=True, text=True, timeout=timeout)

    def wait_ssh(self, timeout=600):
        end = time.time() + timeout
        while time.time() < end:
            if self.proc.poll() is not None:
                return False
            try:
                if self.ssh("true", timeout=15).returncode == 0:
                    return True
            except subprocess.TimeoutExpired:
                pass
            time.sleep(3)
        return False

    def poweroff(self, timeout=180):
        try:
            self.ssh("sudo systemctl poweroff", timeout=20)
        except subprocess.TimeoutExpired:
            pass
        try:
            self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            self.kill()

    def kill(self):
        self.proc.kill()
        self.proc.wait()


def qimg(*args):
    subprocess.run(["qemu-img", *args], check=True, capture_output=True)


def builder(extra_disk, throttle=None):
    """The cloud image, with the test disk as its second disk."""
    disk = os.path.join(WORK, "builder.qcow2")
    if os.path.exists(disk):
        os.unlink(disk)
    qimg("create", "-q", "-f", "qcow2", "-F", "qcow2", "-b", os.path.join(CACHE, "base.qcow2"), disk, "8G")
    vm = VM("builder", [disk, extra_disk], 2231, seed=True, throttle=throttle)
    if not vm.wait_ssh():
        vm.kill()
        raise SystemExit("builder VM did not come up")
    return vm


def push(vm, files, dest):
    """Copy local files into dest/ on the VM (tar over SSH)."""
    tar = subprocess.run(["tar", "-C", "/", "-cf", "-"] + [f.lstrip("/") for f in files],
                         capture_output=True, check=True).stdout
    subprocess.run(SSH + ["-p", str(vm.port), "tester@127.0.0.1",
                          f"mkdir -p {dest} && tar -C {dest} --strip-components=0 -xf -"],
                   input=tar, check=True, capture_output=True)


def build(variant):
    image = os.path.join(WORK, f"enc-{variant}.qcow2")
    say(f"build {variant}")
    qimg("create", "-q", "-f", "qcow2", image + ".new", "10G")
    vm = builder(image + ".new")
    try:
        files = [os.path.join(REPO, p) for p in (
            "tests/vm-encrypt-build.sh", "home/.local/bin/clave-encrypt",
            "home/.local/share/clave/clave-encrypt-offline.sh")]
        push(vm, files, "/tmp/in")
        flat = "mkdir -p /tmp/f && find /tmp/in -type f -exec cp {} /tmp/f/ \\;"
        r = vm.ssh(f"{flat} && sudo bash /tmp/f/vm-encrypt-build.sh {variant} /dev/vdb /tmp/f", timeout=3600)
        sys.stdout.write(r.stdout[-2000:] + r.stderr[-2000:])
        ok = check(r.returncode == 0 and f"BUILD-OK {variant}" in r.stdout, f"{variant}: test system built")
    finally:
        vm.poweroff()
    if ok:
        os.replace(image + ".new", image)


EXPECT = r'''
set timeout 7200
log_user 1
spawn sudo bash /mnt/b/clave-encrypt-offline.sh
expect {
    -re {Type ENCRYPT to start:} { send "ENCRYPT\r"; exp_continue }
    -re {(?i)(enter|verify|current|new)[^\r\n]*passphrase[^\r\n]*:} {
        # The prompt comes before echo is turned off, which throws away
        # anything already typed: wait a moment, like a person would.
        sleep 0.5; send "$env(PW)\r"; exp_continue }
    -re {Press Enter when the recovery key} { send "\r"; exp_continue }
    -re {Type 'yes' in capital letters} { sleep 0.5; send "YES\r"; exp_continue }
    eof
}
catch wait result
exit [lindex $result 3]
'''


def offline(image, variant, interrupt=False):
    """Stage 3: the offline script from the builder ("live USB")."""
    vm = builder(image, throttle="15000000" if interrupt else None)
    try:
        r = vm.ssh("sudo pacman -Sy --noconfirm --needed expect >/dev/null && sudo mkdir -p /mnt/b "
                   "&& sudo mount /dev/vdb1 /mnt/b && sha256sum /mnt/b/clave-encrypt-offline.sh", timeout=600)
        check(r.returncode == 0, f"{variant}: offline script found on the boot partition")
        vm.ssh("cat > /tmp/offline.exp", stdin=EXPECT)
        cmd = f"PW='{PASSPHRASE}' expect /tmp/offline.exp"
        if interrupt:
            p = subprocess.Popen(SSH + ["-p", str(vm.port), "tester@127.0.0.1", cmd],
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            seen = ""
            for line in p.stdout:
                seen += line
                if "encrypting" in line:
                    time.sleep(20)
                    break
            vm.kill()
            p.kill()
            check("encrypting" in seen, f"{variant}: VM powered off during reencrypt")
            return offline(image, variant + " (resumed)")
        r = vm.ssh(cmd, timeout=7200)
        out = r.stdout + r.stderr
        with open(os.path.join(WORK, f"offline-{variant.split()[0]}.log"), "a") as f:
            f.write(out)
        plain = re.sub(r"\x1b\[[0-9;]*m|\x1b\][^\x1b]*\x1b\\", "", out)
        keys = re.findall(r"\b(?:[cbdefghijklnrtuv]{8}-){7}[cbdefghijklnrtuv]{8}\b", plain)
        check(r.returncode == 0 and "Encryption done." in out, f"{variant}: offline stage done")
        if "resumed" in variant:
            check("resuming the interrupted encryption" in out, f"{variant}: resumed with --resume-only")
        vm.poweroff()
        return keys[0] if keys else None
    except BaseException:
        vm.kill()
        raise


def run(variant):
    base = "grub" if variant == "interrupted" else variant
    src = os.path.join(WORK, f"enc-{base}.qcow2")
    if not os.path.exists(src):
        build(base)
    image = os.path.join(WORK, f"run-{variant}.qcow2")
    vars_ = os.path.join(WORK, f"run-{variant}.vars")
    for f in (image, vars_):
        if os.path.exists(f):
            os.unlink(f)
    qimg("create", "-q", "-f", "qcow2", "-F", "qcow2", "-b", src, image)
    shutil.copy(OVMF_VARS, vars_)
    port = 2232

    # 1. checks and prepare in the running system
    vm = VM(f"{variant}-1", [image], port, uefi_vars=vars_)
    if not check(vm.wait_ssh(), f"{variant}: test system boots"):
        vm.kill()
        return
    # The scripts from this checkout, not the ones from when the image was built.
    push(vm, [os.path.join(REPO, p) for p in ("home/.local/bin/clave-encrypt",
                                                "home/.local/share/clave/clave-encrypt-offline.sh")], "/tmp/in")
    vm.ssh("find /tmp/in -name clave-encrypt -type f -exec install -m755 {} ~/.local/bin/ \\; && "
           "find /tmp/in -name clave-encrypt-offline.sh -exec install -m755 {} ~/.local/share/clave/ \\;")
    check(vm.ssh("~/.local/bin/clave-encrypt status").stdout.strip() == "Off", f"{variant}: status Off before")
    r = vm.ssh("~/.local/bin/clave-encrypt checks", stdin="I have a full backup\nqemu snapshot\n")
    if not check(r.returncode == 0, f"{variant}: checks pass"):
        sys.stdout.write(r.stdout[-3000:] + r.stderr[-3000:])
    r = vm.ssh("sudo ~/.local/bin/clave-encrypt prepare", timeout=900)
    check(r.returncode == 0 and "SHA-256" in r.stdout, f"{variant}: prepare")
    if r.returncode:
        sys.stdout.write(r.stdout[-3000:] + r.stderr[-3000:])
    # Pick the new entry for the next boot of the test system, as the user
    # would in the boot menu.
    pick = {"grub": "sudo grub-reboot clave-encrypted",
            "sdboot": "sudo bootctl set-oneshot clave-encrypted.conf",
            "limine": "n=$(grep -c '^/' /boot/limine.conf) && sudo sed -i \"1i default_entry: $n\" /boot/limine.conf"}[base]
    check(vm.ssh(pick).returncode == 0, f"{variant}: next boot picks Clave (encrypted)")
    vm.poweroff()

    # 2. offline stage
    recovery = offline(image, variant, interrupt=(variant == "interrupted"))
    check(bool(recovery), f"{variant}: recovery key shown")

    # 3. first boot of the encrypted entry, then finish
    vm = VM(f"{variant}-2", [image], port, uefi_vars=vars_)
    vm.answer = PASSPHRASE
    if not check(vm.wait_ssh(900), f"{variant}: encrypted entry boots with the passphrase"):
        vm.kill()
        return
    st = vm.ssh("~/.local/bin/clave-encrypt status --json").stdout.strip()
    check('"status":"On"' in st, f"{variant}: status On after the offline stage ({st})")
    r = vm.ssh("sudo ~/.local/bin/clave-encrypt finish", timeout=900)
    check(r.returncode == 0 and "Disk Encryption is On" in r.stdout, f"{variant}: finish")
    if r.returncode:
        sys.stdout.write(r.stdout[-3000:] + r.stderr[-3000:])
    if base == "limine":
        vm.ssh("sudo sed -i '/^default_entry:/d' /boot/limine.conf")
    vm.poweroff()

    # 4. the normal entry, unlocked with the recovery key
    vm = VM(f"{variant}-3", [image], port, uefi_vars=vars_)
    vm.answer = recovery or PASSPHRASE
    if check(vm.wait_ssh(900), f"{variant}: normal entry boots after finish (recovery key)"):
        st = vm.ssh("~/.local/bin/clave-encrypt status").stdout.strip()
        check(st == "On", f"{variant}: status On after finish")
        if base == "grub":
            check(vm.ssh("findmnt -nvo SOURCE /home").stdout.strip() == "/dev/mapper/chome",
                  f"{variant}: /home unlocked by its key file")
        if base == "limine":
            # swapon shows /dev/dm-N; lsblk gives the mapper name.
            if not check("cswap" in vm.ssh("swapon --show=NAME --noheadings | xargs -r lsblk -dno NAME").stdout.split(),
                         f"{variant}: swap on a random key"):
                r = vm.ssh("swapon --show; lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS; sudo cat /etc/crypttab /etc/fstab; "
                           "systemctl --failed --no-legend; journalctl -b --no-pager | grep -i -E 'cswap|swap|systemd-cryptsetup' | tail -30")
                sys.stdout.write(r.stdout + r.stderr)
        vm.poweroff()
    else:
        vm.kill()
    for f in (image, vars_):
        os.unlink(f)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("build", "run"):
        raise SystemExit(__doc__)
    os.makedirs(WORK, exist_ok=True)
    names = sys.argv[2:] or (VARIANTS if sys.argv[1] == "build" else VARIANTS + ["interrupted"])
    for n in names:
        (build if sys.argv[1] == "build" else run)(n)
    say("ALL PASSED" if not failed else f"{len(failed)} FAILED: " + "; ".join(failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
