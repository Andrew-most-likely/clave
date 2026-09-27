-- Hyprland plugins, built from source for the installed Hyprland by
-- ~/.local/share/clave/rebuild-plugins.sh (a pacman hook runs it after
-- every Hyprland upgrade).
--   hypr-minimize  forwards the minimize request to Quickshell (genie effect)
--   hyprbars       title bars with traffic-light buttons
local settings = require("clave.settings")
local plugins = os.getenv("HOME") .. "/.local/share/clave"

pcall(hl.plugin.load, plugins .. "/hypr-minimize/hypr-minimize.so")

local bars = settings.traffic_lights ~= false
    and pcall(hl.plugin.load, plugins .. "/hyprbars/hyprbars.so")
    and hl.plugin.hyprbars ~= nil

if bars then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height            = 28,
                bar_color             = "rgba(2a2a2cf0)",
                ["col.text"]          = "rgba(ffffffcc)",
                bar_text_font         = "Inter",
                bar_text_size         = 10,
                bar_text_weight       = "semibold",
                bar_text_align        = "center",
                bar_buttons_alignment = "left",
                bar_padding           = 12,
                bar_button_padding    = 8,
                bar_blur              = true,
                bar_part_of_window    = true,
                bar_precedence_over_border = true,
                icon_on_hover         = true,
                inactive_button_color = "rgba(ffffff30)",
                -- Double-clicking the title bar zooms.
                on_double_click       = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
            },
        },
    })
    -- Left to right: close, minimize (genie into the Dock), full screen.
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(ff5f57)", fg_color = "rgb(4d0000)", size = 12, icon = "×",
        action = [[hyprctl dispatch 'hl.dsp.window.close()']],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(febc2e)", fg_color = "rgb(5a3e00)", size = 12, icon = "−",
        action = "qs ipc call minimize active",
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(28c840)", fg_color = "rgb(004d00)", size = 12, icon = "+",
        action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })']],
    })

    -- Apps that draw their own title bar (GTK/libadwaita, Firefox, Steam) would
    -- get two sets of traffic lights.
    hl.window_rule({
        name  = "clave-no-bar-csd",
        match = { class = "^(firefox|steam|org\\.gnome\\..*|nautilus|.*pavucontrol|blueman-.*|nm-connection-editor|nwg-.*|virt-manager|satty|xdg-desktop-portal-gtk|polkit-gnome-authentication-agent-1|io\\.elementary\\..*|fsearch|io\\.github\\.cboxdoerfer\\.FSearch)$" },
        ["hyprbars:no_bar"] = true,
    })
    hl.window_rule({
        name  = "clave-no-bar-about",
        match = { title = "^About This Computer$" },
        ["hyprbars:no_bar"] = true,
    })
end

-- Safety net for the pacman hook: if a plugin did not load at login (built for
-- another Hyprland), offer a rebuild. It asks first, since it downloads code.
hl.on("hyprland.start", function()
    local loaded = {}
    for _, p in ipairs(hl.get_loaded_plugins()) do
        loaded[p.name] = true
    end
    if not ((loaded["hyprbars"] or settings.traffic_lights == false) and loaded["hypr-minimize"]) then
        hl.exec_cmd("~/.local/share/clave/rebuild-plugins.sh --ask --reload")
    end
end)
