-- Keyboard shortcuts. Super is the Command key.
-- Every bind has a description: Super+/ lists them (clave-keybinds).
-- To change one in custom.lua: hl.unbind("SUPER + X"), then hl.bind(...).
local mod = "SUPER"
local function bind(keys, action, description, opts)
    opts = opts or {}
    opts.description = description
    hl.bind(keys, action, opts)
end
local exec = hl.dsp.exec_cmd

-- Apps and system
bind(mod .. " + SPACE",          exec("clave-search"),                 "Search")
bind(mod .. " + SUPER_L",        exec("clave-search"),                 "Search (tap Super)", { release = true })
bind(mod .. " + A",              exec("clave-apps"),                 "Apps")
bind(mod .. " + TAB",            exec("qs ipc call overview toggle"), "Overview")
bind(mod .. " + RETURN",         exec("kitty"),                           "Terminal")
bind(mod .. " + E",              exec("nautilus --new-window"),           "Files")
bind(mod .. " + B",              exec("xdg-open https://"),               "Web browser")
bind(mod .. " + COMMA",          exec("qs ipc call settings open general"), "System Settings")
bind(mod .. " + N",              exec("swaync-client -t -sw"),            "Notification Center")
bind(mod .. " + CTRL + N",       exec("qs ipc call controlcenter toggle"), "Control Center")
bind(mod .. " + V",              exec("clave-clipboard"),                 "Clipboard history")
bind(mod .. " + CTRL + SPACE",   exec("clave-emoji"),                     "Emoji & Symbols")
bind(mod .. " + SLASH",          exec("clave-keybinds"),                  "Keyboard shortcuts")
bind(mod .. " + P",              exec("~/.config/hypr/scripts/display-mode.sh"), "Display mode")
bind(mod .. " + ALT + ESCAPE",   exec("qs ipc call forcequit open"),      "Force Quit Applications")

-- Session
bind(mod .. " + L",              exec("clave-power -l"),                  "Lock Screen")
bind(mod .. " + CTRL + Q",       exec("clave-power -l"),                  "Lock Screen")
bind(mod .. " + SHIFT + ESCAPE", exec("qs ipc call menubar open system"),  "System menu")

-- Screenshots (Shift+Super+3/4/5)
bind(mod .. " + SHIFT + 3",      exec("clave-screenshot screen"),         "Screenshot: whole screen")
bind(mod .. " + SHIFT + 4",      exec("clave-screenshot area"),           "Screenshot: selected area")
bind(mod .. " + SHIFT + 5",      exec("clave-screenshot window"),         "Screenshot: active window")
bind("PRINT",                    exec("clave-screenshot area"),           "Screenshot: selected area")
bind(mod .. " + SHIFT + 6",      exec("clave-screenshot text"),           "Copy text from screen area (OCR)")

-- Appearance
bind(mod .. " + SHIFT + W",      exec("clave-wallpaper --random"),        "Next wallpaper")
bind(mod .. " + SHIFT + N",      exec("clave-nightlight toggle"),         "Night Light on/off")

-- Windows
bind(mod .. " + Q",              exec("qs ipc call menubar quit"),        "Quit app")
bind(mod .. " + W",              hl.dsp.window.close(),                   "Close window")
bind(mod .. " + H",              exec("qs ipc call menubar hide"),        "Hide app")
bind(mod .. " + ALT + H",        exec("qs ipc call menubar hideOthers"),  "Hide others")
bind(mod .. " + M",              exec("qs ipc call minimize active"),     "Minimize window to Dock")
bind(mod .. " + CTRL + F",       hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Full screen")
bind(mod .. " + F",              hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Full screen")
bind(mod .. " + CTRL + M",       hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),  "Zoom (maximize)")
bind(mod .. " + T",              hl.dsp.window.float({ action = "toggle" }), "Float / tile window")
bind(mod .. " + ALT + T",        function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.pin())
end, "Float and keep on top")
bind(mod .. " + J",              hl.dsp.layout("togglesplit"),            "Toggle split direction")
bind(mod .. " + K",              hl.dsp.layout("swapsplit"),              "Swap split")
bind(mod .. " + G",              hl.dsp.group.toggle(),                   "Group windows (tabs)")
bind("ALT + TAB",                function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end, "Switch windows")

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    bind(mod .. " + " .. dir,         hl.dsp.focus({ direction = dir }),                "Focus window " .. dir)
    bind(mod .. " + ALT + " .. dir,   hl.dsp.window.swap({ direction = dir:sub(1, 1) }), "Swap window " .. dir)
end
local step = 100
bind(mod .. " + SHIFT + right", hl.dsp.window.resize({ x = step,  y = 0, relative = true }), "Wider",   { repeating = true })
bind(mod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -step, y = 0, relative = true }), "Narrower", { repeating = true })
bind(mod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0, y = step,  relative = true }), "Taller",  { repeating = true })
bind(mod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0, y = -step, relative = true }), "Shorter", { repeating = true })
bind(mod .. " + mouse:272",     hl.dsp.window.drag(),   "Move window with the mouse",   { mouse = true })
bind(mod .. " + mouse:273",     hl.dsp.window.resize(), "Resize window with the mouse", { mouse = true })

-- Spaces (workspaces). Super+1..0 opens the Space on the focused screen.
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key,           hl.dsp.focus({ workspace = i, on_current_monitor = true }), "Go to Space " .. i)
    bind(mod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }),                      "Move window to Space " .. i)
end
bind(mod .. " + CTRL + right",  hl.dsp.focus({ workspace = "e+1" }), "Next Space")
bind(mod .. " + CTRL + left",   hl.dsp.focus({ workspace = "e-1" }), "Previous Space")
bind(mod .. " + mouse_down",    hl.dsp.focus({ workspace = "e+1" }), "Next Space")
bind(mod .. " + mouse_up",      hl.dsp.focus({ workspace = "e-1" }), "Previous Space")
bind(mod .. " + S",             hl.dsp.workspace.toggle_special("scratchpad"), "Show / hide scratchpad")
bind(mod .. " + SHIFT + S",     function()
    hl.dispatch(hl.dsp.window.move({ workspace = "special:scratchpad" }))
end, "Move window to scratchpad")

-- Game mode: no animations, blur, shadows, gaps or rounding. Off reloads the config.
local gamemode = false
bind(mod .. " + ALT + G", function()
    gamemode = not gamemode
    if gamemode then
        hl.config({
            animations = { enabled = false },
            decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 },
            general    = { gaps_in = 0, gaps_out = 0, border_size = 0 },
        })
        hl.exec_cmd("notify-send -a 'Game Mode' 'Game Mode on'")
    else
        hl.exec_cmd("hyprctl reload")
    end
end, "Game mode on/off")
bind(mod .. " + CTRL + R", exec("hyprctl reload"), "Reload Hyprland config")

-- Media keys with on-screen display and a volume click
local key = { locked = true, repeating = true }
local sound = " && clave-sound audio-volume-change"
bind("XF86AudioRaiseVolume",  exec("swayosd-client --output-volume raise" .. sound), "Volume up", key)
bind("XF86AudioLowerVolume",  exec("swayosd-client --output-volume lower" .. sound), "Volume down", key)
bind("XF86AudioMute",         exec("swayosd-client --output-volume mute-toggle"),     "Mute", { locked = true })
bind("XF86AudioMicMute",      exec("swayosd-client --input-volume mute-toggle"),      "Mute microphone", { locked = true })
bind("XF86MonBrightnessUp",   exec("swayosd-client --brightness raise"),              "Brightness up", key)
bind("XF86MonBrightnessDown", exec("swayosd-client --brightness lower"),              "Brightness down", key)
bind("XF86AudioPlay",         exec("playerctl play-pause"), "Play / pause", { locked = true })
bind("XF86AudioPause",        exec("playerctl play-pause"), "Play / pause", { locked = true })
bind("XF86AudioNext",         exec("playerctl next"),       "Next track",   { locked = true })
bind("XF86AudioPrev",         exec("playerctl previous"),   "Previous track", { locked = true })

-- Lid: with a second screen, closing the lid turns the laptop screen off.
-- Sleep / lock on lid close is logind's (System Settings > Battery).
bind("switch:on:Lid Switch",  exec("~/.config/hypr/scripts/display-mode.sh --hotplug"), "Lid closed", { locked = true })
bind("switch:off:Lid Switch", exec("~/.config/hypr/scripts/display-mode.sh --hotplug"), "Lid opened", { locked = true })
