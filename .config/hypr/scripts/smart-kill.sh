#!/usr/bin/env bash
# Super+Q wrapper. For windows on a normal workspace this is just
# `hyprctl dispatch killactive`. For windows on a special workspace
# (per-app tray windows: discord, spotify, docker, term, …) we instead
# toggle the workspace away — keeps the app alive and one keypress brings
# it back, matching the launch-on-demand contract in toggle-or-launch.sh.
set -eu

# `workspace:` line in `hyprctl activewindow` looks like
#   workspace: -97 (special:discord)
# extract just the name after `special:` if present.
special=$(hyprctl activewindow \
    | sed -n 's/^[[:space:]]*workspace:[[:space:]]*-[0-9]*[[:space:]]*(special:\([^)]*\)).*/\1/p')

if [ -n "$special" ]; then
    exec hyprctl dispatch togglespecialworkspace "$special"
else
    exec hyprctl dispatch killactive
fi
