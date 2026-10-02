#!/usr/bin/env bash
# Unit tests for Network Identity (SEC-7): clave-netid renders every profile
# into a scratch root, reset restores what was there, and clave-synshape
# rewrites saved SYNs correctly. The rendered rulesets are loaded into a
# throwaway network namespace when the kernel allows it (unshare -rn).
# Needs no root and changes nothing outside a temp folder.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tool="$repo/system/harden/usr/local/bin/clave-netid"
synshape="$repo/system/harden/usr/local/bin/clave-synshape"
profiles="$repo/system/harden/usr/share/clave/netid"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3: got '$1', want '$2'"; fi; }
has()  { if grep -qE -- "$2" "$1"; then ok "$3"; else fail "$3: /$2/ not in $1"; sed 's/^/      /' "$1"; fi; }
hasnt() { if grep -qE -- "$2" "$1"; then fail "$3: /$2/ in $1"; else ok "$3"; fi; }

export CLAVE_NETID_ROOT="$tmp/root" CLAVE_NETID_PROFILES="$profiles" CLAVE_NETID_DHCPCD="$tmp/dhcpcd"
netid() { bash "$tool" "$@"; }
etc=$tmp/root/etc
mkdir -p "$etc"
printf 'original dhcpcd.conf\n' > "$etc/dhcpcd.conf"

# --- profiles are complete --------------------------------------------------
keys="name ttl timestamps syn_order syn_window dhcp_prl dhcp_vendor dhcp_max_message_size hostname ping closed ua ua_platform ua_oscpu"
for p in windows macos iphone android linux; do
    f=$profiles/$p.conf
    missing=""
    for k in $keys; do grep -q "^$k=" "$f" || missing="$missing $k"; done
    eq "$missing" "" "$p.conf has every key"
done

# --- bad input is refused ---------------------------------------------------
if netid apply 'windows;rm' 0 2>/dev/null; then fail "bad profile accepted"; else ok "bad profile refused"; fi
if netid apply windows 2 2>/dev/null; then fail "bad stealth accepted"; else ok "bad stealth refused"; fi
if netid apply ../etc/passwd 0 2>/dev/null; then fail "path accepted"; else ok "path refused"; fi
if netid hostname 'x; reboot' 2>/dev/null; then fail "bad uuid accepted"; else ok "bad uuid refused"; fi
eq "$(netid status | sed -n 's/^profile=//p')" off "status off before apply"

# --- Windows ----------------------------------------------------------------
netid apply windows 0 >/dev/null
has "$etc/dhcpcd.conf" '^vendorclassid MSFT 5\.0$' "windows: vendor class"
has "$etc/dhcpcd.conf" '^clientid$' "windows: client id is the MAC"
hasnt "$etc/dhcpcd.conf" '^duid' "windows: no DUID"
has "$etc/dhcpcd.conf" 'dhcp_max_message_size' "windows: no option 57"
has "$etc/dhcpcd.conf" '^option subnet_mask, routers, domain_name_servers, domain_name, router_discovery, static_routes, vendor_encapsulated_options, netbios_name_servers, netbios_node_type, netbios_scope, domain_search, classless_static_routes, ms_classless_static_routes, wpad_url$' "windows: request list"
has "$etc/sysctl.d/99-zz-clave-netid.conf" '^net\.ipv4\.ip_default_ttl = 128$' "windows: TTL 128"
has "$etc/sysctl.d/99-zz-clave-netid.conf" '^net\.ipv4\.tcp_timestamps = 0$' "windows: no timestamps"
hasnt "$etc/sysctl.d/99-zz-clave-netid.conf" 'arp_ignore' "windows: no stealth ARP"
has "$etc/clave/netid/dhcp" '^ttl=128$' "windows: DHCP TTL for patched dhcpcd"
has "$etc/clave/netid/dhcp" '^prl=1,3,6,15,31,33,43,44,46,47,119,121,249,252$' "windows: option 55 order"
has "$etc/clave/netid/nft.rules" 'netid_in icmp type echo-request drop' "windows: no ping replies"
has "$etc/clave/netid/nft.rules" '^add rule inet hardening netid_closed drop$' "windows: closed ports dropped"
hasnt "$etc/clave/netid/nft.rules" 'tcp reset' "windows: no RST"
hasnt "$etc/clave/netid/nft.rules" 'queue' "windows: queue rule only after the self-test"
has "$etc/clave/netid/syn" '^order=mss,nop,ws,nop,nop,sok$' "windows: SYN order"
has "$etc/clave/netid/portal" '^ua=.*Windows NT 10\.0' "windows: portal user agent"
has "$etc/NetworkManager/conf.d/60-clave-netid.conf" '^dhcp=dhcpcd$' "NetworkManager uses dhcpcd"
has "$etc/NetworkManager/conf.d/60-clave-netid.conf" '^wifi\.cloned-mac-address=random$' "random MAC"
has "$etc/clave/netid/backup/dhcpcd.conf" 'original' "first apply keeps the old dhcpcd.conf"
uuid=0f6c4a8e-2b1d-4c3e-9f00-123456789abc
netid hostname $uuid
has "$etc/clave/netid/hostname" '^DESKTOP-[A-Z0-9]{7}$' "windows: DESKTOP-XXXXXXX hostname"
eq "$(netid status | sed -n 's/^profile=//p')" windows "status windows"
has <(netid status) '^profiles=off:Off;windows:Windows 11;macos:macOS;iphone:iPhone;android:Android;linux:Linux$' "status lists the profiles with their labels"

# --- macOS with Stealth -----------------------------------------------------
netid apply macos 1 >/dev/null
hasnt "$etc/dhcpcd.conf" 'MSFT' "macos: no Windows vendor class"
has "$etc/dhcpcd.conf" '^vendorclassid$' "macos: empty vendor class"
has "$etc/dhcpcd.conf" 'broadcast_address' "macos: option 28 not requested"
has "$etc/dhcpcd.conf" 'ipv6_only_preferred' "macos: dhcpcd ignores option 108"
has "$etc/clave/netid/dhcp" '^prl=1,121,3,6,15,108,114,119,252,95,44,46$' "macos: option 55 order"
has "$etc/sysctl.d/99-zz-clave-netid.conf" '^net\.ipv4\.ip_default_ttl = 64$' "macos: TTL 64"
has "$etc/sysctl.d/99-zz-clave-netid.conf" '^net\.ipv4\.conf\.all\.arp_ignore = 1$' "stealth: ARP only for own address"
has "$etc/clave/netid/nft.rules" 'netid_in drop$' "stealth: drop new inbound"
has "$etc/clave/netid/nft.rules" 'netid_in udp sport 67 udp dport 68 return' "stealth: DHCP replies still pass"
has "$etc/clave/netid/syn" '^window=65535$' "macos: SYN window"
netid hostname $uuid
eq "$(cat "$etc/clave/netid/hostname")" "" "stealth: no DHCP hostname"
has "$etc/clave/netid/backup/dhcpcd.conf" 'original' "second apply keeps the first backup"
eq "$(netid status | sed -n 's/^stealth=//p')" 1 "status stealth"

# --- the others -------------------------------------------------------------
netid apply iphone 0 >/dev/null
netid hostname $uuid
eq "$(cat "$etc/clave/netid/hostname")" iPhone "iphone: hostname"
has "$etc/clave/netid/nft.rules" 'echo-request limit rate 5/second accept' "iphone: answers ping"
has "$etc/clave/netid/nft.rules" 'reject with tcp reset$' "iphone: RST on closed ports"
eq "$(tail -n1 "$etc/clave/netid/nft.rules")" "insert rule inet hardening netid_closed meta pkttype host meta l4proto tcp limit rate 5/second reject with tcp reset" "tcp reset rule is the last line (nft 1.1 parser)"
netid apply android 0 >/dev/null
has "$etc/dhcpcd.conf" '^vendorclassid android-dhcp-14$' "android: vendor class"
has "$etc/dhcpcd.conf" 'dhcp_lease_time, dhcp_renewal_time, dhcp_rebinding_time' "android: options 51, 58, 59"
hasnt "$etc/dhcpcd.conf" 'nooption.*broadcast_address' "android: option 28 requested"
has "$etc/clave/netid/syn" '^order=$' "android: no SYN rewrite"
netid apply linux 0 >/dev/null
has "$etc/clave/netid/dhcp" '^prl=$' "linux: dhcpcd's own option 55"
has "$etc/dhcpcd.conf" '^option domain_name_servers, domain_name, domain_search$' "linux: stock request list"

# --- status reads the dhcpcd build ------------------------------------------
eq "$(netid status | sed -n 's/^dhcp_patch=//p')" no "status: stock dhcpcd"
printf 'xx/etc/clave/netid/dhcpxx' > "$tmp/dhcpcd"
eq "$(netid status | sed -n 's/^dhcp_patch=//p')" yes "status: patched dhcpcd"

# --- nftables ---------------------------------------------------------------
if command -v nft >/dev/null && unshare -rn nft -c -f "$repo/system/harden/etc/nftables.conf" 2>/dev/null; then
    for p in windows macos iphone android linux; do
        for s in 0 1; do
            netid apply $p $s >/dev/null
            render_syn=$(sed -n '/^render_nft_syn() {/,/^}/p' "$tool")
            # the queue rule the helper adds after the self-test
            bash -c "queue=7071; $render_syn; render_nft_syn" > "$tmp/syn.rules"
            if unshare -rn sh -c "nft -f '$repo/system/harden/etc/nftables.conf' && nft -f '$etc/clave/netid/nft.rules' && nft -f '$etc/clave/netid/nft.rules' && nft -f '$tmp/syn.rules'" 2>"$tmp/nft.err"; then
                ok "nft loads $p stealth=$s"
            else
                fail "nft $p stealth=$s: $(head -n1 "$tmp/nft.err")"
            fi
        done
    done
else
    echo "skip: nft rulesets (no nft or no network namespace here)"
fi

# --- reset ------------------------------------------------------------------
netid reset >/dev/null
eq "$(cat "$etc/dhcpcd.conf")" "original dhcpcd.conf" "reset restores dhcpcd.conf"
[ ! -e "$etc/clave/netid" ] && ok "reset removes /etc/clave/netid" || fail "reset left /etc/clave/netid"
[ ! -e "$etc/sysctl.d/99-zz-clave-netid.conf" ] && ok "reset removes sysctl file" || fail "sysctl file left"
[ ! -e "$etc/NetworkManager/conf.d/60-clave-netid.conf" ] && ok "reset removes NM file" || fail "NM file left"
rm "$etc/dhcpcd.conf"
netid apply windows 0 >/dev/null
netid reset >/dev/null
[ ! -e "$etc/dhcpcd.conf" ] && ok "reset removes a dhcpcd.conf that was not there" || fail "dhcpcd.conf left"

# --- SYN rewriter on saved packets ------------------------------------------
python3 - "$synshape" <<'EOF' || fails=$((fails + 1))
import importlib.machinery, importlib.util, struct, sys
loader = importlib.machinery.SourceFileLoader("synshape", sys.argv[1])
spec = importlib.util.spec_from_loader("synshape", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
bad = 0
def check(cond, what):
    global bad
    print(("ok:   " if cond else "FAIL: ") + what)
    bad += not cond

def opts(pkt):
    ihl = (pkt[0] & 15) * 4
    doff = (pkt[ihl + 12] >> 4) * 4
    return pkt[ihl + 20:ihl + doff]

def valid(pkt):
    ihl = (pkt[0] & 15) * 4
    tcp = pkt[ihl:]
    pseudo = pkt[12:20] + struct.pack("!BBH", 0, 6, len(tcp))
    return m.checksum(pkt[:ihl]) == 0 and m.checksum(pseudo + tcp) == 0 and \
        struct.unpack("!H", pkt[2:4])[0] == len(pkt)

def make(opt_hex, window=64240):
    """An IPv4 SYN from 10.9.9.1 to 10.9.9.2:80 with these options, checksums set."""
    o = bytes.fromhex(opt_hex)
    tcp = bytearray(struct.pack("!HHIIBBHHH", 34858, 80, 0x41F40D1C, 0, (20 + len(o)) // 4 << 4, 0x02, window, 0, 0) + o)
    ip = bytearray(struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(tcp), 0x79C3, 0x4000, 64, 6, 0,
                               bytes([10, 9, 9, 1]), bytes([10, 9, 9, 2])))
    ip[10:12] = struct.pack("!H", m.checksum(bytes(ip)))
    tcp[16:18] = struct.pack("!H", m.checksum(bytes(ip[12:20]) + struct.pack("!BBH", 0, 6, len(tcp)) + bytes(tcp)))
    return bytes(ip + tcp)

# Linux SYN options as this kernel sends them, with tcp_timestamps=0 and =1
# (the first is a capture: the checksums must match the kernel's).
no_ts = bytes.fromhex("4500003479c3400040069aec0a0909010a090902882a005041f40d1c000000008002faf0767e0000020405b4010104020103030a")
check(make("020405b4010104020103030a") == no_ts, "test packet builder matches a captured SYN")
ts = make("020405b40402080ad8dd56cf0000000001030307")
win = "mss,nop,ws,nop,nop,sok".split(",")
mac = "mss,nop,ws,nop,nop,ts,sok,eol".split(",")

check(valid(no_ts) and valid(ts), "test packets have valid checksums")
w = m.rewrite(no_ts, win)
check(opts(w) == bytes.fromhex("020405b40103030a01010402"), "windows order: mss,nop,ws,nop,nop,sok")
check(valid(w), "windows: checksums and length valid")
w2 = m.rewrite(ts, win)
check(opts(w2) == bytes.fromhex("020405b40103030701010402") and valid(w2), "windows drops the timestamp, keeps ws 7")
mc = m.rewrite(ts, mac, 65535)
check(opts(mc) == bytes.fromhex("020405b4" "01" "030307" "01" "01" "080ad8dd56cf00000000" "0402" "00" "00"), "macos order with timestamp and eol padding")
check(valid(mc) and len(mc) == len(ts) + 4, "macos: header grew by 4 bytes, checksums valid")
check(struct.unpack("!H", mc[34:36])[0] == 65535, "macos: SYN window 65535")
check(m.rewrite(no_ts, ["mss","nop","nop","sok","nop","ws"]) is None, "no change: packet passes untouched")
synack = bytearray(no_ts); synack[33] = 0x12
check(m.rewrite(bytes(synack), win) is None, "SYN-ACK is never touched")
tfo = bytearray(no_ts); tfo[40:44] = bytes([34, 2, 1, 1])
check(m.rewrite(bytes(tfo), win) is None, "unknown option (Fast Open): untouched")
check(m.rewrite(no_ts[:30], win) is None, "short packet: untouched")
broken = bytearray(no_ts); broken[41] = 40
check(m.rewrite(bytes(broken), win) is None, "bad option length: untouched")
for a, b in ((no_ts, win), (ts, win), (ts, mac)):
    r = m.rewrite(a, b)
    check(set(o for o in m.parse_options(opts(r))) <= set(m.parse_options(opts(a))), "never adds an option")
    check(all(m.parse_options(opts(r))[k] == m.parse_options(opts(a))[k] for k in m.parse_options(opts(r))), "option values unchanged")
sys.exit(1 if bad else 0)
EOF

echo
if [ "$fails" -eq 0 ]; then echo "netid-unit: all passed"; else echo "netid-unit: $fails failed"; exit 1; fi
