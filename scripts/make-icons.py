#!/usr/bin/env python3
"""Writes Clave's app icons (PROJECT_PLAN.md BR-12) into the Clave-icons theme.

    scripts/make-icons.py           write the SVG files
    scripts/make-icons.py --check   fail when a written file differs (CI)

Each icon is a rounded square with a two-stop gradient and a white glyph of a
generic idea. The glyphs are drawn here from basic shapes; none is traced from
another icon. Edit an icon in ICONS below, run this script, and commit the SVG
files with it.
"""
import math
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "home/.local/share/icons/Clave-icons/scalable/apps")
# The Apps button's icon is also in hicolor, for the personal option's theme (BR-10).
APPS_HICOLOR = os.path.join(REPO, "home/.local/share/icons/hicolor/scalable/apps/clave-apps.svg")
W = "#fff"


def gear(teeth=8, r_out=36, r_in=28, hole=11):
    pts = []
    for i in range(teeth * 4):
        a = math.pi * 2 * i / (teeth * 4) - math.pi / 2
        r = r_out if i % 4 in (1, 2) else r_in
        pts.append(f"{64 + r * math.cos(a):.1f} {64 + r * math.sin(a):.1f}")
    return (f'<path fill="{W}" fill-rule="evenodd" d="M{" L".join(pts)}Z '
            f'M{64 + hole} 64a{hole} {hole} 0 1 0 -{2 * hole} 0a{hole} {hole} 0 1 0 {2 * hole} 0Z"/>')


def stroke(d, w=8):
    return (f'<path fill="none" stroke="{W}" stroke-width="{w}" stroke-linecap="round" '
            f'stroke-linejoin="round" d="{d}"/>')


# name: (top color, bottom color, glyph, icon names the apps ask for).
# BG in a glyph is replaced by the bottom color, for cut-outs.
ICONS = {
    "apps": ("#8a7dff", "#5446d8",
             ''.join(f'<rect x="{x}" y="{y}" width="28" height="28" rx="8" fill="#fff"/>'
                     for y in (32, 68) for x in (32, 68)),
             ["clave-apps"]),
    "screenshot": ("#38b6ff", "#1477c9",
                   stroke("M34 52V36h16M78 36h16v16M94 76v16H78M50 92H34V76", 8)
                   + f'<circle cx="64" cy="64" r="9" fill="{W}"/>',
                   ["clave-screenshot"]),
    "files": ("#4aa8ff", "#1c6fe0",
              f'<path fill="{W}" opacity=".7" d="M30 40h22l7 7h39a4 4 0 0 1 4 4v8H26V44a4 4 0 0 1 4-4z"/>'
              f'<rect x="26" y="54" width="76" height="40" rx="5" fill="{W}"/>',
              ["org.gnome.Nautilus", "system-file-manager"]),
    "activity": ("#43d18a", "#1f9d5c",
                 '<rect x="31" y="66" width="14" height="28" rx="4" fill="#fff"/>'
                 '<rect x="57" y="48" width="14" height="46" rx="4" fill="#fff"/>'
                 '<rect x="83" y="32" width="14" height="62" rx="4" fill="#fff"/>',
                 ["utilities-system-monitor", "org.gnome.SystemMonitor"]),
    "backups": ("#e87a4f", "#c0512a",
                ''.join(f'<rect x="32" y="{y}" width="64" height="16" rx="8" fill="#fff"/>'
                        f'<circle cx="84" cy="{y + 8}" r="3.5" fill="BG"/>' for y in (32, 56, 80)),
                ["timeshift"]),
    "calculator": ("#6f7f99", "#44516a",
                   stroke("M44 34v24M32 46h24M72 46h24M34 72l20 20M54 72 34 92M72 76h24M72 88h24", 7),
                   ["org.gnome.Calculator", "accessories-calculator"]),
    "calendar": ("#ff6a5b", "#e0392b",
                 f'<rect x="28" y="36" width="72" height="62" rx="9" fill="{W}"/>'
                 '<rect x="42" y="27" width="8" height="18" rx="4" fill="#fff"/>'
                 '<rect x="78" y="27" width="8" height="18" rx="4" fill="#fff"/>'
                 + ''.join(f'<rect x="{x}" y="{y}" width="11" height="9" rx="2.5" fill="BG"/>'
                           for y in (56, 72) for x in (38, 58, 78)),
                 ["x-office-calendar"]),
    "camera": ("#8a939f", "#5d6672",
               f'<rect x="46" y="36" width="36" height="14" rx="5" fill="{W}"/>'
               f'<rect x="26" y="44" width="76" height="50" rx="11" fill="{W}"/>'
               '<circle cx="64" cy="69" r="17" fill="BG"/><circle cx="64" cy="69" r="9" fill="#fff"/>',
               ["org.gnome.Snapshot"]),
    "clock": ("#3b4a8f", "#222c5e",
              f'<circle cx="64" cy="64" r="36" fill="{W}"/>'
              '<path fill="none" stroke="BG" stroke-width="7" stroke-linecap="round" d="M64 64V40M64 64l16 10"/>'
              '<circle cx="64" cy="64" r="5" fill="BG"/>',
              ["org.gnome.clocks"]),
    "console": ("#2f5d62", "#173a3e",
                ''.join(f'<circle cx="34" cy="{y}" r="5" fill="#fff"/>' for y in (40, 56, 72, 88))
                + stroke("M48 40h48M48 56h34M48 72h44M48 88h26", 7),
                ["org.gnome.Logs"]),
    "disks": ("#7d8fa3", "#4f6177",
              f'<rect x="26" y="46" width="76" height="38" rx="9" fill="{W}"/>'
              '<circle cx="88" cy="65" r="5" fill="BG"/>'
              '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M38 65h32"/>',
              ["org.gnome.DiskUtility", "gnome-disks"]),
    "document": ("#d65bb0", "#a3307f",
                 f'<path fill="{W}" d="M40 26h32l20 20v50a6 6 0 0 1-6 6H40a6 6 0 0 1-6-6V32a6 6 0 0 1 6-6z"/>'
                 '<path fill="BG" opacity=".35" d="M72 26v20h20z"/>'
                 '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M44 62h36M44 74h36M44 86h24"/>',
                 ["org.gnome.Papers", "org.gnome.Evince", "org.gnome.Evince-symbolic"]),
    "images": ("#3fd0e8", "#1597b8",
               f'<rect x="26" y="34" width="76" height="60" rx="9" fill="{W}"/>'
               '<path fill="BG" d="M34 86l20-24 12 13 9-9 19 20z"/>'
               '<circle cx="84" cy="50" r="7" fill="BG"/>',
               ["org.gnome.Loupe"]),
    "passwords": ("#a45fd1", "#7536a3",
                  f'<circle cx="46" cy="64" r="15" fill="none" stroke="{W}" stroke-width="9"/>'
                  + stroke("M61 64h37M88 64v13M77 64v10", 9),
                  ["org.gnome.seahorse.Application", "seahorse"]),
    "text": ("#5b7bb8", "#3a5790",
             f'<rect x="34" y="26" width="60" height="76" rx="9" fill="{W}"/>'
             '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M44 44h40M44 56h40M44 68h22"/>'
             '<path stroke="BG" stroke-width="4" stroke-linecap="round" d="M76 66v24M70 66h12M70 90h12"/>',
             ["org.gnome.TextEditor"]),
    "sysinfo": ("#3d8bfd", "#1f5fd0",
                f'<circle cx="64" cy="64" r="36" fill="{W}"/>'
                '<circle cx="64" cy="45" r="6" fill="BG"/><rect x="58" y="56" width="12" height="30" rx="5" fill="BG"/>',
                ["hardinfo2"]),
    "videos": ("#8e5cf7", "#6232d1",
               f'<rect x="26" y="36" width="76" height="56" rx="11" fill="{W}"/>'
               '<path fill="BG" d="M56 50l24 14-24 14z"/>',
               ["org.gnome.Showtime"]),
    "store": ("#34c66b", "#1f9a4b",
              f'<path fill="{W}" d="M32 50h64l-6 46a6 6 0 0 1-6 5H44a6 6 0 0 1-6-5z"/>'
              + stroke("M50 56V44a14 14 0 0 1 28 0v12", 6),
              ["io.github.kolunmi.Bazaar"]),
    "settings": ("#6e8fb3", "#46668c", gear(), ["org.quickshell", "preferences-system"]),
    "terminal": ("#3a3f4b", "#1d2027",
                 stroke("M34 46l18 18-18 18", 9) + '<rect x="60" y="78" width="34" height="9" rx="4.5" fill="#fff"/>',
                 ["kitty", "utilities-terminal"]),
    "archive": ("#c9a46a", "#9c7a3f",
                f'<rect x="28" y="34" width="72" height="18" rx="5" fill="{W}"/>'
                f'<path fill="{W}" d="M33 56h62v34a6 6 0 0 1-6 6H39a6 6 0 0 1-6-6z"/>'
                '<rect x="52" y="64" width="24" height="8" rx="4" fill="BG"/>',
                ["org.gnome.FileRoller", "file-roller"]),
    "update": ("#3ca0ff", "#1a6fd6",
               stroke("M64 32v44M46 60l18 18 18-18M38 94h52", 9),
               ["system-software-update", "software-update-available"]),
    # The Clave keystone (BR-2), the same path as docs/assets/brand/clave.svg,
    # for About This Computer.
    "logo": ("#3a3a40", "#1d1d22",
             '<path fill="#fff" stroke="#fff" stroke-width="5" stroke-linejoin="round" '
             'transform="translate(64 66) scale(.82) translate(-50 -51)" '
             'd="M12 20 Q50 -2 88 20 L70 92 Q50 80 30 92 Z"/>',
             ["clave-logo"]),
}


def svg(top, bottom, glyph):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">\n'
            f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient></defs>\n'
            '<rect x="6" y="6" width="116" height="116" rx="27" fill="url(#g)"/>\n'
            f'{glyph.replace("BG", bottom)}\n</svg>\n')


def main():
    check = "--check" in sys.argv[1:]
    want = {}
    for top, bottom, glyph, names in ICONS.values():
        for n in names:
            want[n + ".svg"] = svg(top, bottom, glyph)
    os.makedirs(OUT, exist_ok=True)
    bad = []
    for name, text in sorted(want.items()):
        p = os.path.join(OUT, name)
        old = open(p).read() if os.path.exists(p) else None
        if old != text:
            bad.append(name)
            if not check:
                with open(p, "w") as f:
                    f.write(text)
    hicolor = open(APPS_HICOLOR).read() if os.path.exists(APPS_HICOLOR) else None
    if hicolor != want["clave-apps.svg"]:
        bad.append("hicolor/clave-apps.svg")
        if not check:
            with open(APPS_HICOLOR, "w") as f:
                f.write(want["clave-apps.svg"])
    extra = sorted(set(os.listdir(OUT)) - set(want))
    if check:
        for n in bad + extra:
            print(f"out of date: {n} (run scripts/make-icons.py)", file=sys.stderr)
        sys.exit(1 if bad or extra else 0)
    for n in extra:
        os.unlink(os.path.join(OUT, n))
    print(f"{len(want)} icons, {len(bad)} written, {len(extra)} removed")


if __name__ == "__main__":
    main()
