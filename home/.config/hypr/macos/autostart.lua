-- Session startup.
local mac = require("macos.settings")

hl.on("hyprland.start", function()
    -- Hand the Wayland environment to systemd and D-Bus services, then restart
    -- the portals so they pick it up.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal")

    hl.exec_cmd("hyprctl setcursor macOS 24")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("macos-gtk-apply")

    -- Wallpaper, then the shell: menu bar, dock, Mission Control, settings.
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("macos-wallpaper --restore")
    hl.exec_cmd("qs")

    hl.exec_cmd("swaync")
    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("hypridle")

    -- Clipboard history (Super+V). Turn off in System Settings > Privacy.
    if mac.clipboard_history ~= false then
        hl.exec_cmd("wl-paste --type text --watch cliphist store")
        hl.exec_cmd("wl-paste --type image --watch cliphist store")
    end

    -- Apps in ~/.config/autostart and /etc/xdg/autostart (systemd runs them).
    hl.exec_cmd("systemctl --user start xdg-desktop-autostart.target")

    hl.exec_cmd("macos-sound desktop-login")
end)

-- Re-apply the saved display mode, scale and wallpaper when a screen is
-- plugged in or removed.
for _, ev in ipairs({ "monitor.added", "monitor.removed" }) do
    hl.on(ev, function()
        hl.exec_cmd("~/.config/hypr/scripts/display-mode.sh --hotplug")
    end)
end
