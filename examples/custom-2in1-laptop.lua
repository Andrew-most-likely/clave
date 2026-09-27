-- Example custom.lua for a 2-in-1 laptop with a 2880x1800 14.5" touchscreen
-- and a pen. Copy the parts you need into ~/.config/hypr/custom.lua.

-- 1.5x scale: 1920x1200 of room on a sharp panel.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.5 })

-- Touchscreen and pen follow the laptop panel, not the external screen.
hl.config({
    input = {
        touchdevice = { output = "eDP-1" },
        tablet      = { output = "eDP-1" },
    },
})

-- XWayland apps render at 1x (force_zero_scaling); Steam scales its own UI.
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1.5")

-- Rotate screen and touch input with the device (AUR: iio-hyprland-git).
hl.on("hyprland.start", function()
    hl.exec_cmd("iio-hyprland eDP-1")
end)

-- Super+Shift+F: search files by name (FSearch).
hl.bind("SUPER + SHIFT + F", hl.dsp.exec_cmd("fsearch"), { description = "Search files" })
