-- Trackpad gestures.
-- Hyprland keeps the first gesture registered for each finger count and
-- direction, and this file loads before custom.lua, so custom.lua cannot
-- replace these gestures.

-- Swipe left or right with three or four fingers: switch Spaces
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- Swipe up with three fingers: Overview. Swipe down: leave it.
hl.gesture({ fingers = 3, direction = "up", action = function()
    hl.exec_cmd("qs ipc call overview open")
end })
hl.gesture({ fingers = 3, direction = "down", action = function()
    hl.exec_cmd("qs ipc call overview close")
end })

-- Pinch in with four fingers: Apps
hl.gesture({ fingers = 4, direction = "pinchin", action = function()
    hl.exec_cmd("clave-apps")
end })

-- Spread four fingers: toggle full screen
hl.gesture({ fingers = 4, direction = "pinchout", action = function()
    hl.dispatch(hl.dsp.window.fullscreen({ action = "toggle" }))
end })
