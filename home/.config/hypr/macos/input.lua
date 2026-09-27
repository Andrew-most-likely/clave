-- Keyboard, mouse and trackpad. Values come from System Settings.
local mac = require("macos.settings")
local caps = mac.caps_lock or ""

hl.config({
    input = {
        kb_layout      = mac.kb_layout or "us",
        kb_options     = caps,  -- e.g. "ctrl:nocaps"; System Settings > Keyboard
        repeat_rate    = mac.repeat_rate or 25,
        repeat_delay   = mac.repeat_delay or 600,
        follow_mouse   = 1,
        sensitivity    = mac.mouse_speed or 0,
        accel_profile  = mac.mouse_accel == false and "flat" or "adaptive",
        natural_scroll = mac.mouse_natural == true, -- mice only; trackpad below
        left_handed    = mac.left_handed == true,
        touchpad = {
            natural_scroll       = mac.natural_scroll ~= false,
            tap_to_click         = mac.tap_to_click ~= false,
            disable_while_typing = true,
            clickfinger_behavior = true, -- two-finger click = right click
        },
    },
})
