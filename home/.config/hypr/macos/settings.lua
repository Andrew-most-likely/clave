-- Choices made in System Settings. Quickshell (MacOS/MacSettings.qml) writes
-- ~/.config/macos-look/hypr.lua; a missing file or key means the default.
local mac = {}
local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/macos-look/hypr.lua")
if ok and type(t) == "table" then
    mac = t
end
return mac
