// hypr-minimize: Hyprland ignores minimize requests from apps (the yellow
// button in GTK/Firefox title bars sends xdg_toplevel.set_minimized, X11 apps
// send _NET_WM_STATE_HIDDEN). This plugin forwards them as the IPC event
//   minimized>>ADDRESS,1
// so the Quickshell dock can animate the window into its icon and park it on
// special:minimized. It changes nothing else.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/EventManager.hpp>

#include <format>
#include <unordered_map>

inline HANDLE PHANDLE = nullptr;

struct SWatch {
    CHyprSignalListener state;
};

// One state listener per window, keyed by the window pointer.
static std::unordered_map<Desktop::View::CWindow*, SWatch> g_watches;
static CHyprSignalListener                                  g_openListener;
static CHyprSignalListener                                  g_destroyListener;

static void postMinimize(PHLWINDOWREF ref) {
    const auto w = ref.lock();
    if (!w)
        return;
    g_pEventManager->postEvent(SHyprIPCEvent{"minimized", std::format("{:x},1", (uintptr_t)w.get())});
}

static void watch(PHLWINDOW w) {
    if (!w || g_watches.contains(w.get()))
        return;

    PHLWINDOWREF ref = w;
    SWatch       watch;

    if (const auto xdg = w->m_xdgSurface.lock(); xdg && xdg->m_toplevel) {
        WP<CXDGToplevelResource> tl = xdg->m_toplevel;
        watch.state                 = tl->m_events.stateChanged.listen([ref, tl] {
            if (const auto t = tl.lock(); t && t->m_state.requestsMinimize.value_or(false))
                postMinimize(ref);
        });
    } else if (const auto xw = w->m_xwaylandSurface.lock(); xw) {
        WP<CXWaylandSurface> surf = xw;
        watch.state               = xw->m_events.stateChanged.listen([ref, surf] {
            if (const auto s = surf.lock(); s && s->m_state.requestsMinimize.value_or(false))
                postMinimize(ref);
        });
    } else
        return;

    g_watches.emplace(w.get(), std::move(watch));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH)
        throw std::runtime_error("[hypr-minimize] built for a different Hyprland version, rebuild it");

    g_openListener    = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { watch(w); });
    g_destroyListener = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF ref) {
        std::erase_if(g_watches, [](const auto& kv) {
            for (const auto& w : Desktop::windowState()->windows())
                if (w.get() == kv.first)
                    return false;
            return true;
        });
    });

    for (const auto& w : Desktop::windowState()->windows())
        if (w->m_isMapped)
            watch(w);

    return {"hypr-minimize", "Forwards app minimize requests as the IPC event minimized>>ADDRESS,1", "andrew", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_watches.clear();
    g_openListener.reset();
    g_destroyListener.reset();
}
