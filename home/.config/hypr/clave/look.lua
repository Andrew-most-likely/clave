-- Look: thin light borders, big soft shadows, frosted glass.
-- Visual only; windows still tile.
hl.config({
    general = {
        layout           = "dwindle",
        border_size      = 1,
        gaps_in          = 6,
        gaps_out         = { top = 6, right = 10, bottom = 10, left = 10 },
        resize_on_border = true,
        allow_tearing    = false,
        col = {
            active_border   = "rgba(ffffff26)",
            inactive_border = "rgba(ffffff14)",
        },
    },
    decoration = {
        rounding           = 12,
        rounding_power     = 2,
        active_opacity     = 1.0,
        inactive_opacity   = 1.0,
        fullscreen_opacity = 1.0,
        shadow = {
            enabled        = true,
            range          = 40,
            render_power   = 3,
            offset         = { 0, 10 },
            color          = "rgba(00000066)",
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
    misc = {
        disable_hyprland_logo      = true,
        disable_splash_rendering   = true,
        force_default_wallpaper    = 0,
        initial_workspace_tracking = 1,
        on_focus_under_fullscreen  = 1,
        allow_session_lock_restore = true,
    },
})

-- Frosted glass behind the menu bar, dock, Search and notifications.
for _, ns in ipairs({ "clave-menubar", "clave-dock", "rofi", "clave-control-center",
                      "clave-notification-center", "swaync-control-center",
                      "swaync-notification-window" }) do
    hl.layer_rule({ match = { namespace = ns }, blur = true, blur_popups = true, ignore_alpha = 0.05 })
end

-- The genie overlay and Overview draw their own animation, so
-- Hyprland must map them instantly.
hl.layer_rule({ match = { namespace = "clave-genie" }, no_anim = true })
hl.layer_rule({ match = { namespace = "clave-overview" }, no_anim = true })

-- System Settings > Accessibility.
local settings = require("clave.settings")
if settings.reduce_transparency == true then
    hl.config({ decoration = { blur = { enabled = false } } })
end
if settings.increase_contrast == true then
    hl.config({ general = { col = { active_border = "rgba(ffffffb3)", inactive_border = "rgba(ffffff66)" } } })
end
