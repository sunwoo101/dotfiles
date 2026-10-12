local mainMod    = "SUPER"
local TERMINAL   = "kitty"
local BROWSER    = "google-chrome-stable"
local FILES      = "nautilus --new-window"
local CALCULATOR = "gnome-calculator"

local function bind(mods, key, dispatcher, opts)
    local keys = mods == "" and key or (mods .. " + " .. key)
    hl.bind(keys, dispatcher, opts)
end

local function exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

-- Name of the special workspace the active window lives on ("discord"
-- for special:discord), or nil for regular workspaces / no window.
local function active_special()
    local win = hl.get_active_window()
    if not win or not win.workspace or not win.workspace.special then
        return nil
    end
    return (win.workspace.name:gsub("^special:", ""))
end

-- Window-move guard: NOPs when the active window is on a special
-- workspace, so per-app special tray windows (discord, spotify, term,
-- …) can't be ripped off their pinned overlay via keybind. Mouse drag
-- isn't guarded here — that path is caught after-the-fact by
-- special-workspace-guard.sh's snap-back.
local function guarded(dispatcher)
    return function()
        if active_special() then return end
        hl.dispatch(dispatcher)
    end
end

-- Super+Q. Kills the active window on a normal workspace. On a special
-- workspace (per-app tray windows) it toggles the workspace away
-- instead — keeps the app alive and one keypress brings it back,
-- matching the launch-on-demand contract in toggle-or-launch.sh.
local function smart_kill()
    local special = active_special()
    if special then
        hl.dispatch(hl.dsp.workspace.toggle_special(special))
    else
        hl.dispatch(hl.dsp.window.close())
    end
end

-- Toggle the per-app special workspace if the app is already running,
-- otherwise launch it. See scripts/toggle-or-launch.sh — args are
-- <window class> <special workspace name> <launch command>.
local toggleOrLaunch = "~/.config/hypr/scripts/toggle-or-launch.sh"
local function toggle_or_launch(args)
    return exec(toggleOrLaunch .. " " .. args)
end

local screenshot = exec("~/dotfiles/scripts/screenshot.sh selection 1 1")
local dropdown   = toggle_or_launch("kitty-special term kitty --class=kitty-special")
local lock       = exec("qs ipc call lock lock")

-- Applications
bind(mainMod,            "RETURN", exec(TERMINAL))                                  -- Open the terminal
bind(mainMod,            "B",      exec(BROWSER))                                   -- Open the browser
bind(mainMod,            "E",      exec(FILES))                                     -- Open the filemanager
bind(mainMod .. " + CTRL", "C",    exec(CALCULATOR))                                -- Open the calculator
bind(mainMod,            "D",      toggle_or_launch("discord discord discord"))
bind(mainMod,            "S",      toggle_or_launch("spotify spotify spotify-launcher"))
bind(mainMod,            "G",      toggle_or_launch('"GitHub Desktop" github github-desktop'))
bind(mainMod .. " + SHIFT", "W",   exec("livepaper --kill"))                        -- Kill wallpaper
bind(mainMod,            "R",      exec("livepaper --action=random"))               -- Random wallpaper
bind(mainMod,            "N",      exec("livepaper --action=next-wallpaper"))       -- Next wallpaper
bind(mainMod,            "P",      exec("livepaper --action=previous-wallpaper"))   -- Previous wallpaper
bind(mainMod,            "W",      toggle_or_launch("livepaper livepaper livepaper")) -- Open wallpaper manager

-- Windows
bind(mainMod, "Q", smart_kill)                                                       -- Close active window (or hide if on a special workspace)
bind(mainMod, "F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))                -- Set active window to fullscreen
bind(mainMod, "M", hl.dsp.window.fullscreen({ mode = "maximized" }))                 -- Maximize window
bind(mainMod, "T", hl.dsp.window.float({ action = "toggle" }))                       -- Toggle active window into floating mode
bind(mainMod, "H", hl.dsp.focus({ direction = "left" }))                             -- Move focus left
bind(mainMod, "L", hl.dsp.focus({ direction = "right" }))                            -- Move focus right
bind(mainMod, "K", hl.dsp.focus({ direction = "up" }))                               -- Move focus up
bind(mainMod, "J", hl.dsp.focus({ direction = "down" }))                             -- Move focus down
bind(mainMod, "mouse:272", hl.dsp.window.drag(),   { mouse = true })                 -- Move window with the mouse
bind(mainMod, "mouse:273", hl.dsp.window.resize(), { mouse = true })                 -- Resize window with the mouse
bind(mainMod .. " + ALT", "H", guarded(hl.dsp.window.swap({ direction = "left" })))  -- Swap tiled window left
bind(mainMod .. " + ALT", "L", guarded(hl.dsp.window.swap({ direction = "right" }))) -- Swap tiled window right
bind(mainMod .. " + ALT", "K", guarded(hl.dsp.window.swap({ direction = "up" })))    -- Swap tiled window up
bind(mainMod .. " + ALT", "J", guarded(hl.dsp.window.swap({ direction = "down" })))  -- Swap tiled window down
bind("ALT", "Tab", function()                                                        -- Cycle between windows, bring to top
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top" }))
end, { repeating = true })

-- Actions
bind("",                    "PRINT",  screenshot)                                    -- Take a screenshot (selection)
bind(mainMod,               "PRINT",  screenshot)                                    -- Take a screenshot (selection)
bind(mainMod .. " + SHIFT", "S",      screenshot)                                    -- Take a screenshot (selection)
bind(mainMod .. " + CTRL",  "RETURN", exec("qs ipc call launcher toggle"))           -- Open application launcher
bind(mainMod,               "GRAVE",  dropdown)                                      -- Drop-down terminal
bind(mainMod,               "ESCAPE", dropdown)                                      -- Drop-down terminal
bind(mainMod .. " + CTRL",  "L",      lock)                                          -- Lock session
bind(mainMod .. " + ALT",   "L",      lock)                                          -- Lock session

-- Workspaces: SUPER + [0-9] opens, SUPER + SHIFT + [0-9] moves the active window
for i = 1, 10 do
    local key = tostring(i % 10) -- 10 maps to key 0
    bind(mainMod,               key, hl.dsp.focus({ workspace = i }))
    bind(mainMod .. " + SHIFT", key, guarded(hl.dsp.window.move({ workspace = i })))
end

bind(mainMod,               "Tab",        hl.dsp.focus({ workspace = "m+1" }))      -- Open next workspace
bind(mainMod .. " + SHIFT", "Tab",        hl.dsp.focus({ workspace = "m-1" }))      -- Open previous workspace
bind(mainMod .. " + CTRL",  "right",      hl.dsp.focus({ workspace = "m+1" }))      -- Open next workspace
bind(mainMod .. " + CTRL",  "left",       hl.dsp.focus({ workspace = "m-1" }))      -- Open previous workspace
bind(mainMod,               "mouse_down", hl.dsp.focus({ workspace = "e+1" }))      -- Open next workspace
bind(mainMod,               "mouse_up",   hl.dsp.focus({ workspace = "e-1" }))      -- Open previous workspace
bind(mainMod .. " + CTRL",  "down",       hl.dsp.focus({ workspace = "empty" }))    -- Open the next empty workspace
bind(mainMod .. " + CTRL",  "J",          hl.dsp.focus({ workspace = "empty" }))    -- Open the next empty workspace

-- Media keys
bind("", "XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+"))
bind("", "XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"))
bind("", "XF86AudioMute",        exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
bind("", "XF86AudioNext",        exec("playerctl next"))
bind("", "XF86AudioPrev",        exec("playerctl previous"))
bind("", "XF86AudioPlay",        exec("playerctl play-pause"))
bind("", "XF86AudioPause",       exec("playerctl play-pause"))
