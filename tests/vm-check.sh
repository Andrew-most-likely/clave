#!/usr/bin/env bash
# Checks for the clean-system round trip (PROJECT_PLAN.md section 12), run
# inside a test VM as root by a one-shot service at boot. The hardened
# firewall blocks SSH into the VM, so results go to the serial console,
# one "VMCHECK:" line each. Three boots:
#   1. after install.sh: report the system, then run uninstall.sh --system
#      as the test user and reboot
#   2. after the uninstall: report again, then power off
# Set up with:  tests/vm-check.sh --arm USER REPO   (as root, before rebooting)
set -uo pipefail
state=/var/lib/clave-vmcheck

if [ "${1:-}" = --arm ]; then
    mkdir -p "$state"
    printf '%s\n' "$2" > "$state/user"
    printf '%s\n' "$3" > "$state/repo"
    echo install > "$state/stage"
    install -m755 "$0" /usr/local/sbin/clave-vmcheck
    cat > /etc/systemd/system/clave-vmcheck.service <<'EOF'
[Unit]
Description=Clave round-trip check (test VM only)
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/clave-vmcheck
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable clave-vmcheck.service
    exit 0
fi

exec > /dev/ttyS0 2>&1
say() { printf 'VMCHECK: %s\n' "$*"; }
user=$(cat "$state/user") repo=$(cat "$state/repo") stage=$(cat "$state/stage")
sleep 30   # let the boot settle

report() {
    say "stage=$stage kernel=$(uname -r)"
    say "cmdline=$(cat /proc/cmdline)"
    say "failed units: $(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
    local u
    for u in sddm nftables opensnitchd usbguard apparmor auditd bluetooth avahi-daemon cups.socket \
             arch-audit.timer aidecheck.timer paccache.timer; do
        say "unit $u: $(systemctl is-active "$u" 2>/dev/null) / $(systemctl is-enabled "$u" 2>/dev/null)"
    done
    say "plymouth theme: $(plymouth-set-default-theme 2>/dev/null)"
    say "sddm theme: $(grep -h '^Current=' /etc/sddm.conf.d/*.conf 2>/dev/null | tr '\n' ' ')"
    say "clave files: $(find /usr/share/sddm/themes/clave /usr/share/plymouth/themes/clave /var/lib/clave -maxdepth 0 2>/dev/null | tr '\n' ' ')"
    say "home files: $(find "/home/$user/.config/quickshell/Clave" "/home/$user/.local/bin/clave-search" -maxdepth 0 2>/dev/null | tr '\n' ' ')"
    say "apparmor: $(aa-enabled 2>/dev/null)  lockdown: $(cat /sys/kernel/security/lockdown 2>/dev/null)"
}

case "$stage" in
    install)
        report
        say "uninstall: start"
        runuser -u "$user" -- bash -c "cd '$repo' && ./uninstall.sh --system" > "$state/uninstall.log" 2>&1
        say "uninstall: exit $?"
        tail -n 15 "$state/uninstall.log" | sed 's/^/VMCHECK:   /'
        echo uninstalled > "$state/stage"
        systemctl reboot ;;
    uninstalled)
        report
        say "done"
        systemctl disable clave-vmcheck.service
        systemctl poweroff ;;
esac
