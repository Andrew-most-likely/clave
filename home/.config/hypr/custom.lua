-- -----------------------------------------------------
-- Personal overrides (loaded last by hyprland.lua)
-- Windows-style comforts + 2-in-1 laptop setup
-- -----------------------------------------------------

local mainMod = "SUPER"

-- Choices made in System Settings (Quickshell MacOS/MacSettings.qml writes
-- this file). Missing file or keys mean the defaults.
local mac = {}
do
    local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/macos-look/hypr.lua")
    if ok and type(t) == "table" then mac = t end
end

-- -----------------------------------------------------
-- Input: touchpad, touchscreen, stylus
-- -----------------------------------------------------
hl.config({
    input = {
        touchpad = {
            natural_scroll       = mac.natural_scroll ~= false,
            tap_to_click         = mac.tap_to_click ~= false,
            disable_while_typing = true,
            clickfinger_behavior = true, -- two-finger click = right click
        },
        touchdevice = { output = "eDP-1" },
        tablet      = { output = "eDP-1" },
    },
})

-- Mouse and keyboard (System Settings > Mouse, Keyboard). Tracking speed
-- applies to every pointer; natural scrolling here is for mice only.
local caps = mac.caps_lock or ""
hl.config({
    input = {
        sensitivity    = mac.mouse_speed or 0,
        accel_profile  = mac.mouse_accel == false and "flat" or "adaptive",
        natural_scroll = mac.mouse_natural == true,
        left_handed    = mac.left_handed == true,
        repeat_rate    = mac.repeat_rate or 25,
        repeat_delay   = mac.repeat_delay or 600,
        kb_layout      = mac.kb_layout or "us",
        kb_options     = "grp:alt_shift_toggle" .. (caps ~= "" and ("," .. caps) or ""),
    },
})

-- -----------------------------------------------------
-- Display: 2880x1800 on a 14.5" panel -> scale 1.5
-- (1920x1200 effective; overrides monitors.lua, which
-- the settings app / nwg-displays may rewrite)
-- -----------------------------------------------------
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto",
    scale    = 1.5,
})

-- XWayland apps render at 1x (force_zero_scaling), so tell
-- Steam to scale its own UI to match the 1.5 display scale
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1.5")

-- Windows tile by default (Hyprland's normal behavior).
-- Super+T floats one window, Super+Shift+T the whole workspace.

-- -----------------------------------------------------
-- Windows-style keybinds
-- -----------------------------------------------------

-- Tap Super alone = Start menu (cancelled if Super is used in a combo)
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd("~/.config/hypr/scripts/macos-spotlight.sh"), { release = true, description = "Spotlight" })

-- Alt+Tab cycles windows and raises them
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end, { description = "Switch windows" })

-- Super+L locks
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-power -l"), { description = "Lock screen" })

-- Print = screenshot menu, Super+Shift+S = snip a region
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh"), { description = "Screenshot" })
hl.unbind(mainMod .. " + SHIFT + S")
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh --instant-area"), { description = "Snip a region" })

-- Super+I = settings (like Windows Settings)
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("ml4w-dotfiles-settings"), { description = "Open settings" })

-- Super+Shift+F = file search (FSearch)
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("fsearch"), { description = "Search files" })

-- Volume / brightness with on-screen popups (swayosd)
for _, key in ipairs({ "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
                       "XF86AudioMicMute", "XF86MonBrightnessUp", "XF86MonBrightnessDown" }) do
    hl.unbind(key)
end
local osd = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("swayosd-client --output-volume raise"), osd)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("swayosd-client --output-volume lower"), osd)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), osd)
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"), osd)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("swayosd-client --brightness raise"), osd)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"), osd)

-- -----------------------------------------------------
-- Autostart
-- -----------------------------------------------------
hl.on("hyprland.start", function()
    hl.exec_cmd("swayosd-server")
    -- opensnitch-ui starts from ~/.config/autostart/opensnitch_ui.desktop; launching it here too opened a second tray icon.
    hl.exec_cmd("iio-hyprland eDP-1") -- auto-rotate screen + touch
end)

-- -----------------------------------------------------
-- macOS look (Sonoma, dark). Visual only: tiling stays.
-- -----------------------------------------------------
hl.config({
    general = {
        border_size = 1,
        gaps_in     = 6,
        gaps_out    = { top = 6, right = 10, bottom = 10, left = 10 },
        col = {
            active_border   = "rgba(ffffff26)",
            inactive_border = "rgba(ffffff14)",
        },
    },
    decoration = {
        rounding         = 12,
        rounding_power   = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled      = true,
            range        = 40,
            render_power = 3,
            offset       = { 0, 10 },
            color        = "rgba(00000066)",
            color_inactive = "rgba(00000040)",
        },
        blur = {
            enabled  = true,
            size     = 20,
            passes   = 3,
            vibrancy = 0.2,
            noise    = 0.02,
        },
    },
})

-- Animations with a macOS feel
hl.curve("mac", { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
hl.curve("macOut", { type = "bezier", points = { {0.4, 0}, {1, 0.6} } })
hl.animation({ leaf = "windows",       enabled = true, speed = 3,   bezier = "mac",    style = "popin 85%" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 3,   bezier = "mac",    style = "popin 85%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,   bezier = "macOut", style = "popin 85%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 3,   bezier = "mac" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3,   bezier = "mac" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 2.5, bezier = "mac",    style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2,   bezier = "macOut", style = "fade" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 5,   bezier = "mac",    style = "slide" })

-- macOS menu and Spotlight timing (speed is in 100 ms units). Without these,
-- popups and layer fades inherit "fade" above (300 ms), which is far slower
-- than macOS: menus appear instantly and fade out in about 150 ms, Spotlight
-- fades in in about 150 ms and out in about 120 ms.
hl.animation({ leaf = "fadePopupsIn",  enabled = false })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.5, bezier = "mac" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.5, bezier = "mac" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "mac" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.5, bezier = "mac",    style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.2, bezier = "mac",    style = "fade" })

-- Notification Center widgets (Quickshell) get the same glass as the cards.
hl.layer_rule({ match = { namespace = "macos-notification-center" }, blur = true, ignore_alpha = 0.05 })

-- Frosted glass behind the menu bar, dock, Spotlight and notifications
for _, ns in ipairs({ "macos-menubar", "macos-dock", "rofi", "macos-control-center",
                      "swaync-control-center", "swaync-notification-window" }) do
    hl.layer_rule({ match = { namespace = ns }, blur = true, blur_popups = true, ignore_alpha = 0.05 })
end

-- Cmd+Space = Spotlight, Super+A = Launchpad
hl.unbind(mainMod .. " + SPACE")
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("~/.config/hypr/scripts/macos-spotlight.sh"), { description = "Spotlight" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/macos-launchpad.sh"), { description = "Launchpad" })

-- -----------------------------------------------------
-- Multiple screens
-- -----------------------------------------------------
-- Super+P = display mode menu (extend / duplicate / one screen only), like Win+P.
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/display-mode.sh"), { description = "Display mode" })

-- Re-apply the saved display mode, scale and wallpaper when a screen is
-- plugged in, and turn the laptop screen back on when the last one is unplugged.
for _, ev in ipairs({ "monitor.added", "monitor.removed" }) do
    hl.on(ev, function()
        hl.exec_cmd("~/.config/hypr/scripts/display-mode.sh --hotplug")
    end)
end

-- Lid closed with a second screen: laptop screen off; opened: back on.
-- Sleep / lock / shut down on lid close is logind's (System Settings > Battery).
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/scripts/display-mode.sh --hotplug"), { locked = true, description = "Lid closed" })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/display-mode.sh --hotplug"), { locked = true, description = "Lid opened" })

-- Super+1..0 opens the workspace on the focused screen instead of jumping to
-- the screen that has it (a workspace shown on the other screen swaps over).
for i = 1, 10 do
    local key = i % 10
    hl.unbind(mainMod .. " + " .. key)
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i, on_current_monitor = true }), { description = "Focus workspace " .. i .. " on this screen" })
end

-- macOS cursor
hl.env("XCURSOR_THEME", "macOS")
hl.env("XCURSOR_SIZE", "24")
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl setcursor macOS 24")
end)

-- "About This Mac" floats centered like on macOS
hl.window_rule({
    name = "macos-about",
    match = { title = "^About This Mac$" },
    float = true,
    center = true,
    size = "300 460",
})

-- System Settings, Force Quit and "About <App>" (Quickshell MacOS/) float
-- centered like their macOS counterparts.
hl.window_rule({
    name = "macos-system-settings",
    match = { title = "^System Settings$" },
    float = true,
    center = true,
    size = "860 620",
})
hl.window_rule({
    name = "macos-force-quit",
    match = { title = "^Force Quit Applications$" },
    float = true,
    center = true,
    size = "420 440",
})
hl.window_rule({
    name = "macos-app-about",
    match = { class = "^org\\.quickshell$", title = "^About .*" },
    float = true,
    center = true,
})

-- Force Quit Applications (macOS: Cmd-Option-Esc)
hl.bind(mainMod .. " + ALT + Escape", hl.dsp.exec_cmd("qs ipc call forcequit open"), { description = "Force Quit Applications" })

-- macOS sounds (theme in ~/.local/share/sounds/macOS, built by
-- ~/.local/bin/macos-sounds-build). Silent until the sounds are built.
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.local/bin/macos-sound desktop-login")
end)
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && ~/.local/bin/macos-sound audio-volume-change"), { locked = true, repeating = true, description = "Raise volume" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ~/.local/bin/macos-sound audio-volume-change"), { locked = true, repeating = true, description = "Lower volume" })

-- Qt5 apps (e.g. OpenSnitch) need qt5ct; Qt6 apps skip the missing qt5ct
-- plugin and fall through to qt6ct. Both use Kvantum WhiteSur + SF Pro.
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct")

-- Genie minimize. Hyprland ignores the yellow title bar button; the
-- hypr-minimize plugin forwards it to Quickshell (DockApp/Minimizer.qml), which
-- pours the window into its dock icon. Rebuild the plugin after every Hyprland
-- update: ~/.local/share/macos-look/hypr-minimize/build.sh
pcall(hl.plugin.load, os.getenv("HOME") .. "/.local/share/macos-look/hypr-minimize/hypr-minimize.so")
-- The overlay that draws the animation must appear instantly, without a fade.
hl.layer_rule({ match = { namespace = "macos-genie" }, no_anim = true })

-- Mission Control (Quickshell MacOS/MissionControl.qml) draws its own zoom and
-- fade, so Hyprland must map it instantly.
hl.layer_rule({ match = { namespace = "macos-mission-control" }, no_anim = true })

-- -----------------------------------------------------
-- Traffic lights: macOS title bars with close, minimize
-- and full screen buttons (hyprbars, built from source by
-- ~/.local/share/macos-look/hyprbars/build.sh; rebuild it
-- after every Hyprland update, like hypr-minimize).
-- -----------------------------------------------------
if mac.traffic_lights ~= false
    and pcall(hl.plugin.load, os.getenv("HOME") .. "/.local/share/macos-look/hyprbars/hyprbars.so") then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height            = 28,
                bar_color             = "rgba(2a2a2cf0)",
                ["col.text"]          = "rgba(ffffffcc)",
                bar_text_font         = "SF Pro Text",
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
                -- Double-clicking the title bar zooms, as on macOS.
                on_double_click       = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
            },
        },
    })
    -- Left to right: close, minimize (genie into the dock), full screen.
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

    -- GTK apps (GNOME apps, Nautilus, pavucontrol...), Firefox and Steam draw
    -- their own title bars with WhiteSur traffic lights; a second bar would
    -- double them up.
    hl.window_rule({
        name  = "macos-no-bar-csd",
        match = { class = "^(firefox|steam|org\\.gnome\\..*|nautilus|.*pavucontrol|blueman-.*|nm-connection-editor|nwg-.*|virt-manager|satty|xdg-desktop-portal-gtk|polkit-gnome-authentication-agent-1|io\\.elementary\\..*|Mullvad VPN|fsearch|io\\.github\\.cboxdoerfer\\.FSearch)$" },
        ["hyprbars:no_bar"] = true,
    })
    hl.window_rule({
        name  = "macos-no-bar-about",
        match = { title = "^About This Mac$" },
        ["hyprbars:no_bar"] = true,
    })
end

-- Quick Look: Space in Nautilus previews the selected file (sushi). The
-- preview floats centered over the window, as on macOS.
hl.window_rule({
    name  = "macos-quick-look",
    match = { class = "^org\\.gnome\\.NautilusPreviewer$" },
    float = true,
    center = true,
})

-- Safety net for the plugin rebuild the pacman hook does after Hyprland
-- upgrades: if a macOS plugin did not load at login (built for another
-- Hyprland), rebuild both and reload once they are ready.
hl.on("hyprland.start", function()
    local loaded = {}
    for _, p in ipairs(hl.get_loaded_plugins()) do
        loaded[p.name] = true
    end
    local bars_ok = loaded["hyprbars"] or mac.traffic_lights == false
    if not (bars_ok and loaded["hypr-minimize"]) then
        hl.exec_cmd("~/.local/share/macos-look/rebuild-plugins.sh --reload")
    end
end)
