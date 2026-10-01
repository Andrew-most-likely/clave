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
    "books": ("#c98a5a", "#9a5a2e",
              f'<path fill="{W}" d="M64 44C54 37 40 37 28 41v48c12-4 26-4 36 3 10-7 24-7 36-3V41c-12-4-26-4-36 3z"/>'
              '<path stroke="BG" stroke-width="4" d="M64 46v44"/>',
              ["com.github.johnfactotum.Foliate"]),
    "calculator": ("#6f7f99", "#44516a",
                   stroke("M44 34v24M32 46h24M72 46h24M34 72l20 20M54 72 34 92M72 76h24M72 88h24", 7),
                   ["org.gnome.Calculator", "accessories-calculator"]),
    "calendar": ("#ff6a5b", "#e0392b",
                 f'<rect x="28" y="36" width="72" height="62" rx="9" fill="{W}"/>'
                 '<rect x="42" y="27" width="8" height="18" rx="4" fill="#fff"/>'
                 '<rect x="78" y="27" width="8" height="18" rx="4" fill="#fff"/>'
                 + ''.join(f'<rect x="{x}" y="{y}" width="11" height="9" rx="2.5" fill="BG"/>'
                           for y in (56, 72) for x in (38, 58, 78)),
                 ["x-office-calendar", "org.gnome.Calendar"]),
    "camera": ("#8a939f", "#5d6672",
               f'<rect x="46" y="36" width="36" height="14" rx="5" fill="{W}"/>'
               f'<rect x="26" y="44" width="76" height="50" rx="11" fill="{W}"/>'
               '<circle cx="64" cy="69" r="17" fill="BG"/><circle cx="64" cy="69" r="9" fill="#fff"/>',
               ["org.gnome.Snapshot"]),
    "chess": ("#5fae5a", "#3a7d36",
              '<circle cx="64" cy="40" r="12" fill="#fff"/>'
              '<rect x="49" y="54" width="30" height="8" rx="4" fill="#fff"/>'
              '<path fill="#fff" d="M54 62h20l6 24H48z"/>'
              '<rect x="38" y="84" width="52" height="12" rx="6" fill="#fff"/>',
              ["org.gnome.Chess"]),
    "clock": ("#3b4a8f", "#222c5e",
              f'<circle cx="64" cy="64" r="36" fill="{W}"/>'
              '<path fill="none" stroke="BG" stroke-width="7" stroke-linecap="round" d="M64 64V40M64 64l16 10"/>'
              '<circle cx="64" cy="64" r="5" fill="BG"/>',
              ["org.gnome.clocks"]),
    "console": ("#2f5d62", "#173a3e",
                ''.join(f'<circle cx="34" cy="{y}" r="5" fill="#fff"/>' for y in (40, 56, 72, 88))
                + stroke("M48 40h48M48 56h34M48 72h44M48 88h26", 7),
                ["org.gnome.Logs"]),
    "contacts": ("#3cc7b0", "#1a9483",
                 '<circle cx="64" cy="48" r="17" fill="#fff"/>'
                 '<path fill="#fff" d="M30 98c0-19 15-30 34-30s34 11 34 30z"/>',
                 ["x-office-address-book", "org.gnome.Contacts"]),
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
    "fonts": ("#3e3e48", "#1c1c22",
              stroke("M38 96 64 32l26 64M48 76h32", 10),
              ["org.gnome.font-viewer"]),
    "whiteboard": ("#ffc94d", "#f29a1f",
                   stroke("M30 88c8-30 22-44 30-28s6 30 16 26 14-30 22-48", 9),
                   ["com.github.flxzt.rnote"]),
    "images": ("#3fd0e8", "#1597b8",
               f'<rect x="26" y="34" width="76" height="60" rx="9" fill="{W}"/>'
               '<path fill="BG" d="M34 86l20-24 12 13 9-9 19 20z"/>'
               '<circle cx="84" cy="50" r="7" fill="BG"/>',
               ["org.gnome.Loupe"]),
    "passwords": ("#a45fd1", "#7536a3",
                  f'<circle cx="46" cy="64" r="15" fill="none" stroke="{W}" stroke-width="9"/>'
                  + stroke("M61 64h37M88 64v13M77 64v10", 9),
                  ["org.gnome.seahorse.Application", "seahorse"]),
    "maps": ("#2fbf71", "#16904f",
             f'<path fill="{W}" d="M64 102S34 72 34 52a30 30 0 0 1 60 0c0 20-30 50-30 50z"/>'
             '<circle cx="64" cy="52" r="11" fill="BG"/>',
             ["org.gnome.Maps"]),
    "music": ("#20b2aa", "#11807a",
              '<path fill="#fff" d="M52 44l44-12v12L52 56z"/>'
              '<rect x="52" y="44" width="8" height="46" fill="#fff"/><rect x="88" y="32" width="8" height="48" fill="#fff"/>'
              '<ellipse cx="46" cy="90" rx="13" ry="10" fill="#fff"/><ellipse cx="82" cy="80" rx="13" ry="10" fill="#fff"/>',
              ["io.bassi.Amberol"]),
    "notes": ("#ff9f43", "#e87717",
              f'<rect x="32" y="32" width="64" height="68" rx="9" fill="{W}"/>'
              + ''.join(f'<rect x="{x}" y="24" width="7" height="18" rx="3.5" fill="#fff" stroke="BG" stroke-width="3"/>'
                        for x in (44, 60, 76))
              + '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M44 60h40M44 72h40M44 84h26"/>',
              ["accessories-text-editor"]),
    "text": ("#5b7bb8", "#3a5790",
             f'<rect x="34" y="26" width="60" height="76" rx="9" fill="{W}"/>'
             '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M44 44h40M44 56h40M44 68h22"/>'
             '<path stroke="BG" stroke-width="4" stroke-linecap="round" d="M76 66v24M70 66h12M70 90h12"/>',
             ["org.gnome.TextEditor"]),
    "photos": ("#ff7a8a", "#e14b62",
               f'<rect x="24" y="32" width="62" height="48" rx="7" fill="{W}" opacity=".6" transform="rotate(-8 55 56)"/>'
               f'<rect x="40" y="46" width="64" height="50" rx="8" fill="{W}"/>'
               '<path fill="BG" d="M47 89l16-19 10 10 7-7 17 16z"/>',
               ["org.gnome.Shotwell", "shotwell"]),
    "podcasts": ("#2f7fb5", "#1b5a87",
                 '<rect x="52" y="26" width="24" height="46" rx="12" fill="#fff"/>'
                 + stroke("M40 62a24 24 0 0 0 48 0M64 86v12M50 100h28", 7),
                 ["org.gnome.Podcasts"]),
    "reminders": ("#4cd3c2", "#23a393",
                  '<rect x="28" y="34" width="24" height="24" rx="7" fill="#fff"/>'
                  '<rect x="28" y="70" width="24" height="24" rx="7" fill="#fff"/>'
                  '<path fill="none" stroke="BG" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" d="M34 46l5 5 8-10"/>'
                  + stroke("M62 46h38M62 82h38", 8),
                  ["io.github.mrvladus.List"]),
    "scanner": ("#9aa1a9", "#6b737c",
                f'<rect x="26" y="44" width="76" height="12" rx="6" fill="{W}" opacity=".75"/>'
                f'<rect x="26" y="60" width="76" height="34" rx="9" fill="{W}"/>'
                '<path stroke="BG" stroke-width="5" stroke-linecap="round" d="M38 76h52"/>',
                ["org.gnome.SimpleScan"]),
    "remote": ("#4f6bed", "#2f47c4",
               f'<rect x="26" y="30" width="76" height="54" rx="8" fill="none" stroke="{W}" stroke-width="7"/>'
               + stroke("M50 100h28M64 84v16M44 50h34l-8-7M84 64H50l8 7", 6),
               ["org.gnome.Connections"]),
    "sticky": ("#b5d84a", "#88aa22",
               f'<path fill="{W}" d="M36 30h56a6 6 0 0 1 6 6v42L76 100H36a6 6 0 0 1-6-6V36a6 6 0 0 1 6-6z"/>'
               '<path fill="BG" opacity=".45" d="M98 78H82a6 6 0 0 0-6 6v16z"/>',
               ["sticky"]),
    "sysinfo": ("#3d8bfd", "#1f5fd0",
                f'<circle cx="64" cy="64" r="36" fill="{W}"/>'
                '<circle cx="64" cy="45" r="6" fill="BG"/><rect x="58" y="56" width="12" height="30" rx="5" fill="BG"/>',
                ["hardinfo2"]),
    "videos": ("#8e5cf7", "#6232d1",
               f'<rect x="26" y="36" width="76" height="56" rx="11" fill="{W}"/>'
               '<path fill="BG" d="M56 50l24 14-24 14z"/>',
               ["org.gnome.Showtime"]),
    "recorder": ("#ff4d6d", "#d91e45",
                 f'<circle cx="64" cy="64" r="32" fill="none" stroke="{W}" stroke-width="7"/>'
                 '<circle cx="64" cy="64" r="18" fill="#fff"/>',
                 ["org.gnome.SoundRecorder"]),
    "weather": ("#ffb13b", "#f07f17",
                '<circle cx="78" cy="46" r="15" fill="#fff" opacity=".75"/>'
                '<path fill="#fff" d="M42 94a15 15 0 0 1-1-30 22 22 0 0 1 42-6 17 17 0 0 1 3 36z"/>',
                ["org.gnome.Weather"]),
    "store": ("#34c66b", "#1f9a4b",
              f'<path fill="{W}" d="M32 50h64l-6 46a6 6 0 0 1-6 5H44a6 6 0 0 1-6-5z"/>'
              + stroke("M50 56V44a14 14 0 0 1 28 0v12", 6),
              ["io.github.kolunmi.Bazaar"]),
    "settings": ("#6e8fb3", "#46668c", gear(), ["org.quickshell", "preferences-system"]),
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
