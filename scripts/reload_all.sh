#!/usr/bin/env bash
set -uo pipefail
# (no -e: we want to attempt every reload even if one fails)

# call this after editing colors.json + render_configs.sh, OR have the settings
# UI in quickshell call it. quickshell itself reads colors.json directly via
# FileView, so its own widgets update without any of this — this script only
# pokes the non-Quickshell apps that need live updates.

# kitty — live color update via remote control. requires `allow_remote_control yes`
# and `listen_on unix:@mykitty` in kitty.conf. kitty appends -{pid} to abstract
# socket names, so we iterate every running kitty's per-pid socket. only kitty
# windows launched AFTER those settings were added will respond.
if command -v kitty >/dev/null 2>&1 && pgrep -x kitty >/dev/null; then
    _kitty_opacity=$(awk '/^background_opacity/{print $2; exit}' "$HOME/.config/colors.conf")
    for pid in $(pgrep -x kitty); do
        if kitty @ --to=unix:@mykitty-$pid set-colors --all --configured \
                "$HOME/.config/colors.conf" 2>/dev/null; then
            echo "kitty[$pid]: colors reloaded"
        else
            echo "kitty[$pid]: failed (started before remote control was on?)"
        fi
        if [[ -n "$_kitty_opacity" ]]; then
            kitty @ --to=unix:@mykitty-$pid set-background-opacity "$_kitty_opacity" 2>/dev/null \
                && echo "kitty[$pid]: opacity set to $_kitty_opacity" \
                || true
        fi
    done
fi

# hyprland — re-reads its config and any included files
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 \
        && echo "hyprland: config reloaded" \
        || echo "hyprland: reload failed"
fi

# oh-my-posh — embeds theme JSON into bash init code, so live edits don't take
# effect without re-init. our bashrc/ohmyposh has a SIGUSR1 trap that re-runs
# the init; pkill sends the signal to every bash. type something + enter in
# the running shell to see the new prompt.
if pgrep -x bash >/dev/null; then
    pkill -USR1 -x bash 2>/dev/null \
        && echo "bash: SIGUSR1 sent (oh-my-posh will re-init on next prompt)" \
        || echo "bash: signal failed"
fi

# GTK apps — no live theme reload exists. open apps must be restarted to pick
# up new colors. this is a GTK limitation, not something we can work around.
echo "note: GTK apps (nautilus, etc.) won't pick up new colors until restarted"

echo "done."
