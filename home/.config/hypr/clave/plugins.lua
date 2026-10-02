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
    -- Title bars follow Light or Dark in System Settings > Appearance.
    local dark = settings.dark_mode ~= false
    hl.config({
        plugin = {
            hyprbars = {
                bar_height            = 28,
                bar_color             = dark and "rgba(2a2a2cf0)" or "rgba(e8e8eaf0)",
                ["col.text"]          = dark and "rgba(ffffffcc)" or "rgba(1d1d1fcc)",
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
                inactive_button_color = dark and "rgba(ffffff30)" or "rgba(00000026)",
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

    -- Apps that draw their own title bar (GTK/libadwaita, Firefox, Steam,
    -- VS Code, Bazaar) would get two sets of traffic lights. Hyprland does not
    -- tell which windows draw their own, so this is a list (ISSUE-1). Users add
    -- to it in System Settings > Desktop & Dock > Windows. GTK apps without a
    -- header bar (Volume Control, Bluetooth, network connections, nwg-look,
    -- virt-manager) draw no buttons here, so they are not on it.
    hl.window_rule({
        name  = "clave-no-bar-csd",
        match = { class = "^(firefox|steam|code|code-oss|vscodium|codium|io\\.github\\.kolunmi\\.Bazaar|org\\.gnome\\..*|nautilus|satty|xdg-desktop-portal-gtk|polkit-gnome-authentication-agent-1|io\\.elementary\\..*|fsearch|io\\.github\\.cboxdoerfer\\.FSearch)$" },
        ["hyprbars:no_bar"] = true,
    })
    local extra = {}
    for _, class in ipairs(settings.no_bar_apps or {}) do
        -- Clave's own windows always keep their buttons (ClaveSettings.noBarApps).
        if class:match("^[%w._-]+$") and class ~= "org.quickshell" then
            extra[#extra + 1] = (class:gsub("%.", "\\."))
        end
    end
    if #extra > 0 then
        hl.window_rule({
            name  = "clave-no-bar-user",
            match = { class = "^(" .. table.concat(extra, "|") .. ")$" },
            ["hyprbars:no_bar"] = true,
        })
    end
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
