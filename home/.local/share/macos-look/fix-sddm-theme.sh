#!/usr/bin/env bash
# SDDM reads every file in /etc/sddm.conf.d in name order, so the backup
# theme.conf.bak-2026-09-23 (Current=minimal-black) loaded after theme.conf
# and replaced the macOS login theme. Move backups out of that directory.
# Run: sudo ~/.local/share/macos-look/fix-sddm-theme.sh
set -e
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
mkdir -p /etc/sddm.conf.d.backup
shopt -s nullglob
for f in /etc/sddm.conf.d/*.bak* /etc/sddm.conf.d/*~; do
    mv -v "$f" /etc/sddm.conf.d.backup/
done
echo "Theme files now in /etc/sddm.conf.d:"
grep -H "^Current=" /etc/sddm.conf.d/* || true
echo "The macOS login screen appears at the next boot or logout."
