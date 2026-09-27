-- Choices made in System Settings. Quickshell (Clave/ClaveSettings.qml) writes
-- ~/.config/clave/hypr.lua; a missing file or key means the default.
local settings = {}
local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/clave/hypr.lua")
if ok and type(t) == "table" then
    settings = t
end
return settings
