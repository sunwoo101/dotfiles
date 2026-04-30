#!/usr/bin/env bash
# Wrapper for window-moving dispatchers. NOP if the active window lives
# on a special workspace — moving a special window (across workspaces
# OR within its own) breaks the per-app special-workspace contract:
# the window leaves its pinned overlay and the toggle-or-launch flow
# can no longer find it where it expects.
#
# Usage: guard-move.sh <dispatcher> [args...]
#   guard-move.sh swapwindow l
#   guard-move.sh movetoworkspace 3
set -eu

# `workspace:` line in `hyprctl activewindow` looks like
#   workspace: -97 (special:discord)
# Detect any special workspace, regardless of name.
if hyprctl activewindow \
    | grep -qE '^[[:space:]]*workspace:[[:space:]]*-[0-9]+[[:space:]]*\(special:'; then
    exit 0
fi

exec hyprctl dispatch "$@"
