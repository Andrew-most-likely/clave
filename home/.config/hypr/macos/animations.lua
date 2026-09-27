-- macOS timing. Speed is in 100 ms units.
hl.config({ animations = { enabled = true } })

hl.curve("mac",    { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
hl.curve("macOut", { type = "bezier", points = { {0.4, 0}, {1, 0.6} } })

hl.animation({ leaf = "windows",          enabled = true, speed = 3,   bezier = "mac",    style = "popin 85%" })
hl.animation({ leaf = "windowsIn",        enabled = true, speed = 3,   bezier = "mac",    style = "popin 85%" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 2,   bezier = "macOut", style = "popin 85%" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 3,   bezier = "mac" })
hl.animation({ leaf = "border",           enabled = true, speed = 10,  bezier = "default" })
hl.animation({ leaf = "fade",             enabled = true, speed = 3,   bezier = "mac" })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5,   bezier = "mac",    style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3,   bezier = "mac",    style = "slidevert" })

-- Menus appear instantly and fade out in about 150 ms; Spotlight fades in in
-- about 150 ms and out in about 120 ms. Without these, popups and layers
-- inherit "fade" (300 ms).
hl.animation({ leaf = "fadePopupsIn",  enabled = false })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.5, bezier = "mac" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.5, bezier = "mac" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "mac" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.5, bezier = "mac",    style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.2, bezier = "mac",    style = "fade" })
