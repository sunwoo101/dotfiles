#!/usr/bin/env bash
# Toggle the per-app special workspace if a window with $class is already
# open; otherwise launch $cmd. Used by the keybinds in conf/keybinds.conf
# so MOD+<key> behaves the same for every app: hide-when-shown, show-when-
# hidden, launch-when-not-running.
set -eu

class=$1
workspace=$2
shift 2
# Remaining args ("$@") are the launch command and its flags, e.g.
# `kitty --class=kitty-special`. Using exec "$@" instead of a single
# string avoids any shell-parsing surprises with quoted flags.

target="special:${workspace}"

# Snapshot which monitors are involved before any dispatch. cur_mon is
# the focused monitor (where a "show" toggle would land); open_mon is
# the monitor currently displaying special:$workspace, if any.
mons_json=$(hyprctl monitors -j)
cur_mon=$(printf '%s' "$mons_json" | jq -r '.[] | select(.focused == true) | .name')
open_mon=$(printf '%s' "$mons_json" \
    | jq -r --arg ws "$target" \
        '.[] | select(.specialWorkspace.name == $ws) | .name' \
    | head -1)

# Toggle special:$workspace as if the user pressed the keybind from
# $1 (defaults to focused monitor). togglespecialworkspace always acts
# on the *focused* monitor, so we briefly focusmonitor to redirect it
# and restore afterwards. Without this, pressing the keybind from
# monitor 2 while the overlay is open on monitor 1 just opens a fresh
# overlay on 2 instead of toggling the existing one off.
toggle_on() {
    local mon=${1:-$cur_mon}
    if [ -n "$mon" ] && [ -n "$cur_mon" ] && [ "$mon" != "$cur_mon" ]; then
        hyprctl dispatch focusmonitor "$mon" >/dev/null || true
        hyprctl dispatch togglespecialworkspace "$workspace" >/dev/null || true
        hyprctl dispatch focusmonitor "$cur_mon" >/dev/null || true
    else
        hyprctl dispatch togglespecialworkspace "$workspace" >/dev/null || true
    fi
}

# Reconcile displacement. Mouse-dragging a window from a special
# workspace overlay onto another monitor reparents it to the
# destination's regular workspace — Hyprland doesn't emit a
# workspace-change event for that path, so the daemon can't catch it
# live. Sweep here: any window of $class not already on
# special:$workspace gets moved back silently.
reconciled=0
while read -r addr; do
    [ -z "$addr" ] && continue
    hyprctl dispatch movetoworkspacesilent \
        "${target},address:${addr}" >/dev/null || true
    reconciled=1
done < <(hyprctl clients -j \
    | jq -r --arg cls "$class" --arg ws "$target" \
        '.[] | select(.class == $cls and .workspace.name != $ws) | .address')

# If we reconciled, treat this press as a fix-up (not a summon). End
# state matches dormant: window inside the special, overlay hidden.
# Press again to summon.
if [ "$reconciled" = "1" ]; then
    [ -n "$open_mon" ] && toggle_on "$open_mon"
    exit 0
fi

# Normal toggle. If the overlay is open on a non-focused monitor, hide
# it there (matches user expectation that the keybind toggles app
# visibility globally rather than dragging the overlay to the focused
# monitor — Hyprland's default).
if [ -n "$open_mon" ]; then
    toggle_on "$open_mon"
else
    # Overlay hidden everywhere — opening it on the focused monitor is
    # what we want, AND it must be visible BEFORE we exec a launch so
    # the new window doesn't spawn onto a hidden special and require
    # a second keypress to see.
    toggle_on "$cur_mon"
fi

if ! hyprctl clients | grep -q "class: ${class}$"; then
    exec "$@"
fi
