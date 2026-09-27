#!/usr/bin/env python3
# Minimal xdg-desktop-portal Wallpaper backend: makes "Set as Background" in
# Nautilus, Loupe, browsers etc. work on Hyprland by handing the image to macos-wallpaper.
import os, subprocess
from gi.repository import Gio, GLib

XML = """<node><interface name="org.freedesktop.impl.portal.Wallpaper">
  <method name="SetWallpaperURI">
    <arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
    <arg type="s" name="parent_window" direction="in"/><arg type="s" name="uri" direction="in"/>
    <arg type="a{sv}" name="options" direction="in"/><arg type="u" name="response" direction="out"/>
  </method></interface></node>"""
HELPER = os.path.expanduser("~/.local/bin/macos-wallpaper")

def on_call(conn, sender, path, iface, method, params, inv):
    uri = params.unpack()[3]
    ok = subprocess.run([HELPER, uri]).returncode == 0
    inv.return_value(GLib.Variant("(u)", (0 if ok else 2,)))

def on_bus(conn, name):
    conn.register_object("/org/freedesktop/portal/desktop",
                         Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], on_call)

Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.impl.portal.desktop.macos",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, lambda *a: loop.quit())
loop = GLib.MainLoop()
loop.run()
