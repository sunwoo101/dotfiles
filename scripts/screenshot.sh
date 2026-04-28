#!/usr/bin/env bash
# screenshot.sh — Windows-style screenshot helper.
# Usage: screenshot.sh <mode> <save> <clipboard>
#   mode      = full | monitor | window | selection
#   save      = 0 | 1   (write to ~/Pictures/Screenshots/)
#   clipboard = 0 | 1   (copy via wl-copy)
#
# Called by the Quickshell Screenshot.qml modal; can also be invoked
# directly from a keybind (e.g. for a single fixed-mode shortcut).

set -uo pipefail

MODE="${1:-selection}"
SAVE="${2:-1}"
CLIP="${3:-1}"

SHOTS_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SHOTS_DIR"
FILE="$SHOTS_DIR/screenshot-$(date +%Y-%m-%d-%H%M%S).png"

# Resolve the region to capture. Empty REGION → grim takes the full output.
REGION=""
case "$MODE" in
    full) ;;                                  # all outputs
    monitor)
        REGION=$(slurp -o) ;;                 # click an output
    window)
        # show only currently-visible windows (mapped + not hidden + on an
        # active workspace) as hover regions, then click one to pick.
        # Without this, slurp gets regions for windows on other workspaces
        # too — those rectangles cover the screen in confusing ways.
        ACTIVE_WS=$(hyprctl -j monitors | jq '[.[].activeWorkspace.id]')
        REGION=$(hyprctl -j clients \
            | jq -r --argjson ws "$ACTIVE_WS" '.[]
                | select(.mapped == true and .hidden == false
                         and (.workspace.id as $id | $ws | index($id) != null))
                | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' \
            | slurp -r) ;;
    selection)
        REGION=$(slurp) ;;
    *)
        echo "screenshot.sh: unknown mode '$MODE'" >&2
        exit 1 ;;
esac

# slurp returns empty + nonzero on cancel (Esc / right-click) — bail quietly.
if [ "$MODE" != "full" ] && [ -z "$REGION" ]; then
    exit 0
fi

GRIM_ARGS=()
[ -n "$REGION" ] && GRIM_ARGS+=(-g "$REGION")

case "$SAVE$CLIP" in
    11) grim "${GRIM_ARGS[@]}" - | tee "$FILE" | wl-copy ;;
    10) grim "${GRIM_ARGS[@]}" "$FILE" ;;
    01) grim "${GRIM_ARGS[@]}" - | wl-copy ;;
    *)  exit 0 ;;     # neither output requested
esac

# Notify (only meaningful if the daemon is running).
SUMMARY="Screenshot taken"
BODY=""
[ "$SAVE" = "1" ] && BODY="Saved to $FILE"
[ "$CLIP" = "1" ] && BODY="${BODY:+$BODY · }Copied to clipboard"

if command -v notify-send >/dev/null 2>&1; then
    # Custom hint x-screenshot-dir lets Notifications.qml open the folder
    # on click via xdg-open. We don't use -A (which would block notify-send
    # waiting for action callbacks and trip our action-invoke segfault).
    if [ "$SAVE" = "1" ]; then
        notify-send -i "$FILE" \
            -h "string:x-screenshot-dir:$SHOTS_DIR" \
            "$SUMMARY" "$BODY"
    else
        notify-send "$SUMMARY" "$BODY"
    fi
fi
