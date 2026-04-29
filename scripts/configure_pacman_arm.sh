#!/usr/bin/env bash
set -euo pipefail

# ARM: Arch Linux ARM has no [multilib] repo — skip that step entirely.
# Only apply the NoExtract directive to hide the plain Hyprland session file
# from SDDM (same as the x86_64 configure_pacman.sh, minus multilib).

CONF=/etc/pacman.conf

NOEXTRACT='NoExtract = usr/share/wayland-sessions/hyprland.desktop'
if grep -Fxq "$NOEXTRACT" "$CONF"; then
    echo "NoExtract for hyprland.desktop already present"
else
    echo "adding NoExtract for hyprland.desktop to $CONF"
    sudo sed -i "/^\[options\]/a $NOEXTRACT" "$CONF"
    if ! grep -Fxq "$NOEXTRACT" "$CONF"; then
        echo "ERROR: failed to add NoExtract directive — check $CONF manually" >&2
        exit 1
    fi
fi

TARGET=/usr/share/wayland-sessions/hyprland.desktop
if [ -e "$TARGET" ]; then
    echo "removing existing $TARGET"
    sudo rm "$TARGET"
fi
