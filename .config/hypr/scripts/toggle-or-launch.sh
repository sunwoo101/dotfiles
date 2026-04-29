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

# Toggle the workspace first so it's visible BEFORE the window spawns.
# Otherwise, after Super+Q kills the window but leaves the app in the tray,
# launching the app spawns a new window onto the still-hidden special
# workspace and the user has to press the keybind a second time to see it.
hyprctl dispatch togglespecialworkspace "$workspace"

if ! hyprctl clients | grep -q "class: ${class}$"; then
    exec "$@"
fi
