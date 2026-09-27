-- Hyprland permissions (System Settings > Privacy & Security > "Ask before
-- apps capture the screen"). With them on, any other program that tries to
-- record or screenshot the screen, or to load a Hyprland plugin, gets a
-- prompt first. Takes effect after logging in again.
local settings = require("clave.settings")
if settings.enforce_permissions == false then
    return
end

hl.config({ ecosystem = { enforce_permissions = true } })

-- Screen capture without asking: the screenshot and recording tools, the
-- screen sharing portal (it shows its own picker), Overview's live
-- previews, and the color picker.
for _, bin in ipairs({
    "/usr/bin/grim",
    "/usr/bin/wf-recorder",
    "/usr/lib/wf-recorder",
    "/usr/lib/xdg-desktop-portal-hyprland",
    "/usr/bin/quickshell",
    "/usr/bin/hyprpicker",
}) do
    hl.permission({ binary = "^" .. bin:gsub("%.", "\\.") .. "$", type = "screencopy", mode = "allow" })
end

-- Our two plugins (see plugins.lua); any other plugin asks.
local plugins = os.getenv("HOME"):gsub("%.", "\\.") .. "/\\.local/share/clave/(hyprbars/hyprbars|hypr-minimize/hypr-minimize)\\.so"
hl.permission({ binary = "^" .. plugins .. "$", type = "plugin", mode = "allow" })
