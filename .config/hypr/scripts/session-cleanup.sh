#!/usr/bin/env bash
# Watches Hyprland's event socket and stops graphical-session.target
# (and app-graphical.slice) when the compositor exits.
#
# Why: hyprland-uwsm.desktop runs `uwsm start -e -D Hyprland`, which
# skips the wayland-wm service unit. Without that unit, nothing binds
# graphical-session.target to compositor lifetime — the target gets
# pulled up indirectly when the first `uwsm app --` exec-once runs
# (app-graphical.slice Wants= it). On Hyprland exit, the target stays
# active. The next `uwsm start -e` from SDDM then aborts with
# "compositor or graphical-session* target is already active", which
# manifests as either "SDDM restarts on relogin" or a black screen.
#
# This runs as a user systemd service in the default app.slice — which
# is independent of graphical-session.target — so it survives stopping
# its own targets. The script itself is a long-running outer loop so a
# single Hyprland session-end doesn't tear the daemon down; Restart=
# always in the unit file is just a safety net.
set -u

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# Find an instance dir whose Hyprland is *actually* responding. A
# previous session's `.socket2.sock` file frequently lingers in
# $XDG_RUNTIME_DIR/hypr/<HIS>/ after Hyprland exits — the file remains
# but connect() refuses. socat would return instantly and we'd fire
# cleanup against nothing, in a tight Restart loop. hyprctl monitors
# round-trips through the *command* socket (.socket.sock) and only
# succeeds against a live compositor.
find_live_socket() {
    local d his
    for d in "${runtime_dir}/hypr"/*/; do
        [ -S "${d}.socket2.sock" ] || continue
        his=$(basename "$d")
        HYPRLAND_INSTANCE_SIGNATURE=$his hyprctl monitors >/dev/null 2>&1 \
            || continue
        printf '%s\n' "${d}.socket2.sock"
        return 0
    done
    return 1
}

while :; do
    # Wait for a live Hyprland.
    sock=""
    until sock=$(find_live_socket); do sleep 1; done

    # Block until the event socket closes. socat returns on either a
    # failed connect or a remote close.
    socat -u UNIX-CONNECT:"$sock" /dev/null >/dev/null 2>&1 || true

    # Re-check liveness. Brief socat hiccups (compositor reload, IPC
    # blip) shouldn't trigger cleanup against a still-alive session.
    his=$(basename "$(dirname "$sock")")
    if HYPRLAND_INSTANCE_SIGNATURE=$his hyprctl monitors >/dev/null 2>&1; then
        continue
    fi

    systemctl --user stop graphical-session.target app-graphical.slice \
        2>/dev/null || true

    # Pause so a still-present stale socket file from the just-ended
    # session doesn't get re-picked by find_live_socket before the
    # instance dir is reaped. hyprctl liveness-checks every candidate
    # anyway, so this is belt-and-suspenders against fast restart loops.
    sleep 2
done
