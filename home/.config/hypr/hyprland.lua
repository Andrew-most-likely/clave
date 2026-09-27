-- arch-macos-hyprland
-- https://github.com/__GITHUB_REPO__
--
-- Load order: macOS defaults (macos/*.lua), then your files.
-- Do not edit files in macos/: updates replace them. Put your changes in
--   monitors.lua   screens (also written by nwg-displays)
--   custom.lua     everything else; loads last, so it wins

local HOME = os.getenv("HOME")
local function user_file(name)
    local f = io.open(HOME .. "/.config/hypr/" .. name .. ".lua", "r")
    if f then
        f:close()
        require(name)
    end
end

require("macos.env")
require("macos.security")
user_file("monitors")
require("macos.input")
require("macos.gestures")
require("macos.look")
require("macos.animations")
require("macos.layout")
require("macos.rules")
require("macos.binds")
require("macos.autostart")
require("macos.plugins")
user_file("custom")
