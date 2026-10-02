# Optional dhcpcd build for Network Identity

dhcpcd sends DHCP through a raw packet socket, which bypasses netfilter, so its packets always leave with
TTL 64, and it sorts the option 55 request list by number. Without this build, Network Identity sets the
DHCP options but not their order or the TTL, and System Settings says so ("Partial").

`prepare-snippet` patches Arch's dhcpcd so it reads both from `/etc/clave/netid/dhcp`, which `clave-netid`
writes. The file is read once before `main()`, so before privilege separation chroots or sandboxes any
process. Without the file dhcpcd behaves as stock.

Build it with the Arch packaging repo:

    git clone https://gitlab.archlinux.org/archlinux/packaging/packages/dhcpcd.git
    cd dhcpcd
    sed -i '/^prepare() {/r /path/to/Clave-Hyprland/scripts/extra/dhcpcd-netid/prepare-snippet' PKGBUILD
    makepkg -si

A dhcpcd update from pacman replaces the build; rebuild after each one, or use a pacman hook. Checked with
dhcpcd 10.5.2: TTL 128 and a 12-entry request list in a non-numeric order ( `1,121,3,6,15,108,114,119,252,95,44,46`) on the wire,
with privilege separation on.
