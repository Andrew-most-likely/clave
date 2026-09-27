-- clave
-- https://github.com/__GITHUB_REPO__
--
-- Load order: Clave defaults (clave/*.lua), then your files.
-- Do not edit files in clave/: updates replace them. Put your changes in
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

require("clave.env")
require("clave.security")
user_file("monitors")
-- Rules by screen description from System Settings > Displays (SHELL-2).
pcall(dofile, HOME .. "/.config/clave/monitors.lua")
require("clave.input")
require("clave.gestures")
require("clave.look")
require("clave.animations")
require("clave.layout")
require("clave.rules")
require("clave.binds")
require("clave.autostart")
require("clave.plugins")
user_file("custom")
