-- Window rules: dialogs and utility apps float centered.
local function float(name, match, size, extra)
    local rule = { name = name, match = match, float = true, center = true, size = size }
    for k, v in pairs(extra or {}) do
        rule[k] = v
    end
    hl.window_rule(rule)
end

-- Clave windows (Quickshell Clave/)
float("clave-about",           { title = "^About This Computer$" },            "300 460")
float("clave-system-settings", { title = "^System Settings$" },           "860 680")
float("clave-force-quit",      { title = "^Force Quit Applications$" },   "420 440")
float("clave-activity",        { title = "^Activity Monitor$" },          "900 600")
float("clave-app-about",       { class = "^org\\.quickshell$", title = "^About .*" })
-- Quick Look (sushi): Space in Nautilus
float("clave-quick-look",      { class = "^org\\.gnome\\.NautilusPreviewer$" })

-- Utilities
float("pavucontrol",           { class = ".*pavucontrol.*" },             "700 600")
float("blueman-manager",       { class = "^blueman-manager$" },           "800 600")
float("nm-connection-editor",  { class = "^nm-connection-editor$" },      "800 700")
float("nwg-look",              { class = "^nwg-look$" },                  "700 600")
float("nwg-displays",          { class = "^nwg-displays$" },              "900 600")
float("gnome-calculator",      { class = "^org\\.gnome\\.Calculator$" },   "400 600")
float("share-picker",          { class = "^hyprland-share-picker$" },     "600 400", { pin = true })
float("clave-floating",        { class = "^clave-floating$" },            "1000 700")

-- File pickers open where the app asked, not centered.
hl.window_rule({
    name   = "portal-file-picker",
    match  = { class = "^xdg-desktop-portal-gtk$" },
    float  = true,
    size   = "800 600",
})

-- Picture-in-Picture stays on top and never steals focus.
hl.window_rule({
    name  = "picture-in-picture",
    match = { title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]] },
    float = true,
    pin   = true,
    focus_on_activate = false,
    no_initial_focus  = true,
    suppress_event    = "activate",
})
