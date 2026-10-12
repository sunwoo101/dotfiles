-- Require order matters: monitors → visuals → workspaces → … → autostart.
-- visuals' per-class `workspace = "special:* silent"` window rules and
-- workspaces' `monitor` rules must be registered before autostart's
-- `hyprland.start` handler spawns Spotify/Discord/etc., so they land on
-- their pinned specials (and ws 1 lands on the right monitor).

-- `hyprctl reload` may reuse the Lua state; drop cached conf modules so
-- edits and the regenerated conf/colors.lua take effect on reload.
for name in pairs(package.loaded) do
    if name:match("^conf%.") then
        package.loaded[name] = nil
    end
end

require("conf.monitors")
require("conf.visuals")
require("conf.workspaces")
require("conf.animations")
require("conf.autostart")

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    dwindle = {
        preserve_split         = true,
        split_width_multiplier = 1.25,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper    = -1,
        disable_hyprland_logo      = true,
        allow_session_lock_restore = true,
    },
})

---------------
---- INPUT ----
---------------

require("conf.input")

---------------------
---- KEYBINDINGS ----
---------------------

require("conf.keybinds")

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Ignore maximize requests from apps. You'll probably like this.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})
