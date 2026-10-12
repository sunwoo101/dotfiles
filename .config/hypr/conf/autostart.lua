hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.focus({ workspace = 1 }))

    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_ID XDG_SESSION_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP")

    hl.exec_cmd("uwsm app -- qs")
    hl.exec_cmd("uwsm app -- nm-applet --indicator")
    hl.exec_cmd("uwsm app -- blueman-applet")
    hl.exec_cmd("livepaper --restore")
    hl.exec_cmd("livepaper")
    hl.exec_cmd("mpris-proxy")

    hl.exec_cmd("uwsm app -- ~/.config/hypr/scripts/special-workspace-guard.sh")

    -- Bare (not `uwsm app --`): dex forks each .desktop entry then exits, so
    -- wrapping would put every child into one shared `app-*-dex.scope`.
    hl.exec_cmd("dex --autostart --environment Hyprland")
end)
