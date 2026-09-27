-- Environment for Wayland apps, toolkits and the cursor.
local HOME = os.getenv("HOME")

-- ~/.local/bin is appended, not prepended: a user-writable directory must not
-- shadow /usr/bin (a fake "sudo" there would catch your password).
hl.env("PATH", os.getenv("PATH") .. ":" .. HOME .. "/.local/bin")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("DESKTOP_SESSION", "Hyprland")

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("GDK_SCALE", "1")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

-- Qt: Kvantum WhiteSur through qt5ct/qt6ct. Qt6 apps skip the missing qt5ct
-- plugin and fall through to qt6ct.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QS_NO_RELOAD_POPUP", "1")

-- Quickshell resolves app icons through Qt's icon theme, which does not follow
-- the GTK setting; QS_ICON_THEME is what it reads. Take the name from GTK so
-- the dock shows the selected icon theme (applies on next login).
local settings = io.open(HOME .. "/.config/gtk-3.0/settings.ini", "r")
if settings then
    for line in settings:lines() do
        local theme = line:match("^%s*gtk%-icon%-theme%-name%s*=%s*(.-)%s*$")
        if theme and theme ~= "" then
            hl.env("QS_ICON_THEME", theme)
            break
        end
    end
    settings:close()
end

-- Cursor
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- XWayland apps render at 1x instead of blurry upscaling.
hl.config({ xwayland = { force_zero_scaling = true } })
