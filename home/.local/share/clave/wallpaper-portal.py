#!/usr/bin/env python3
# Minimal xdg-desktop-portal Wallpaper backend: makes "Set as Background" in
# Nautilus, Loupe, browsers etc. work on Hyprland by handing the image to
# clave-wallpaper.
#
# Apps must not change the desktop picture behind your back. System Settings >
# Privacy & Security > "Apps can set the wallpaper" (privacy.wallpaperApps):
#   ask     (default) a dialog asks first; closing it means no
#   always  allowed without asking
#   never   always refused
# Only local JPEG, PNG and WebP files are accepted.
import json
import os
import subprocess
import urllib.parse

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

XML = """<node><interface name="org.freedesktop.impl.portal.Wallpaper">
  <method name="SetWallpaperURI">
    <arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
    <arg type="s" name="parent_window" direction="in"/><arg type="s" name="uri" direction="in"/>
    <arg type="a{sv}" name="options" direction="in"/><arg type="u" name="response" direction="out"/>
  </method></interface></node>"""
HELPER = os.path.expanduser("~/.local/bin/clave-wallpaper")
SETTINGS = os.path.expanduser("~/.config/clave/settings.json")
IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
SUCCESS, CANCELLED, FAILED = 0, 1, 2


def policy():
    try:
        with open(SETTINGS) as f:
            value = json.load(f).get("privacy", {}).get("wallpaperApps", "ask")
    except (OSError, ValueError, AttributeError):
        value = "ask"
    return value if value in ("ask", "always", "never") else "ask"


def local_image(uri):
    """The file behind a file:// URI, if it is a readable JPEG, PNG or WebP."""
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "file":
        return None
    path = os.path.realpath(urllib.parse.unquote(parsed.path))
    if not os.path.isfile(path):
        return None
    mime = subprocess.run(["file", "--brief", "--mime-type", "--", path],
                          capture_output=True, text=True).stdout.strip()
    return path if mime in IMAGE_TYPES else None


def app_name(app_id):
    if app_id:
        info = Gio.DesktopAppInfo.new(app_id + ".desktop")
        if info:
            return info.get_display_name()
        return app_id
    return "An app"


def ask(app_id, path, done):
    dialog = Gtk.AlertDialog()
    dialog.set_modal(True)
    dialog.set_message(f"{app_name(app_id)} wants to change your desktop picture")
    dialog.set_detail(os.path.basename(path))
    dialog.set_buttons(["Don't Allow", "Allow"])
    dialog.set_cancel_button(0)
    dialog.set_default_button(0)

    def answered(d, result):
        try:
            done(d.choose_finish(result) == 1)
        except GLib.Error:
            done(False)

    dialog.choose(None, None, answered)


def on_call(conn, sender, path, iface, method, params, inv):
    _handle, app_id, _parent, uri, _options = params.unpack()
    image = local_image(uri)
    mode = policy()
    if image is None or mode == "never":
        inv.return_value(GLib.Variant("(u)", (FAILED if image is None else CANCELLED,)))
        return

    def apply(allowed):
        if not allowed:
            inv.return_value(GLib.Variant("(u)", (CANCELLED,)))
            return
        ok = subprocess.run([HELPER, image]).returncode == 0
        inv.return_value(GLib.Variant("(u)", (SUCCESS if ok else FAILED,)))

    if mode == "always":
        apply(True)
    else:
        ask(app_id, image, apply)


def on_bus(conn, name):
    conn.register_object("/org/freedesktop/portal/desktop",
                         Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], on_call)


Gtk.init()
loop = GLib.MainLoop()
Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.impl.portal.desktop.clave",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, lambda *a: loop.quit())
loop.run()
