-- Keyboard, mouse and trackpad. Values come from System Settings.
local settings = require("clave.settings")
local caps = settings.caps_lock or ""
local layout = settings.kb_layout or "us"

-- Two layouts (for example "us,es"): Alt+Shift switches between them (ISSUE-8).
local options = caps
if layout:find(",", 1, true) then
    options = (caps ~= "" and caps .. "," or "") .. "grp:alt_shift_toggle"
end

hl.config({
    input = {
        kb_layout      = layout,
        kb_options     = options, -- e.g. "ctrl:nocaps"; System Settings > Keyboard
        repeat_rate    = settings.repeat_rate or 25,
        repeat_delay   = settings.repeat_delay or 600,
        follow_mouse   = 1,
        sensitivity    = settings.mouse_speed or 0,
        accel_profile  = settings.mouse_accel == false and "flat" or "adaptive",
        natural_scroll = settings.mouse_natural == true, -- mice only; trackpad below
        left_handed    = settings.left_handed == true,
        touchpad = {
            natural_scroll       = settings.natural_scroll ~= false,
            tap_to_click         = settings.tap_to_click ~= false,
            disable_while_typing = true,
            clickfinger_behavior = true, -- two-finger click = right click
        },
    },
})
