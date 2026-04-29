#!/usr/bin/env bash
set -euo pipefail

# ARM: Arch Linux ARM has no [multilib] repo — skip that step entirely.
#
# Hide hyprland.desktop from SDDM by pointing SDDM at a custom session dir
# (/usr/local/share/wayland-sessions/) that only contains hyprland-uwsm.desktop.
# hyprland.desktop stays in /usr/share/wayland-sessions/ where uwsm finds it.
# No file patching, no pacman hooks, no package cache extraction.

CONF=/etc/pacman.conf
SESSION_DIR=/usr/local/share/wayland-sessions
SDDM_CONF=/etc/sddm.conf.d/sessions.conf

# ---- migrate stale state from prior script versions ----------------------
# Remove stale NoExtract directive and restore hyprland.desktop if deleted.
sudo sed -i '/^NoExtract.*hyprland\.desktop/d' "$CONF"
if [ ! -e /usr/share/wayland-sessions/hyprland.desktop ]; then
    echo "restoring missing hyprland.desktop (reinstalling hyprland)"
    sudo pacman -S --noconfirm --overwrite "*" hyprland
fi
# Remove stale pacman hooks and sync script.
for f in \
    /etc/pacman.d/hooks/hide-hyprland-session.hook \
    /etc/pacman.d/hooks/hyprland-desktop-sync.hook \
    /usr/local/lib/hyprland-desktop-sync.sh
do
    [ -f "$f" ] && sudo rm "$f" && echo "removed stale: $f"
done
# Remove the misplaced hyprland.desktop we wrote to the wrong location.
[ -f "$SESSION_DIR/hyprland.desktop" ] && sudo rm "$SESSION_DIR/hyprland.desktop"

# ---- custom SDDM session dir ---------------------------------------------
# SDDM reads sessions only from its configured SessionDir. By pointing it here
# and symlinking only hyprland-uwsm.desktop, hyprland.desktop stays invisible
# to the greeter while remaining available to uwsm in /usr/share/wayland-sessions/.
sudo mkdir -p "$SESSION_DIR"
if [ ! -L "$SESSION_DIR/hyprland-uwsm.desktop" ]; then
    sudo ln -sf /usr/share/wayland-sessions/hyprland-uwsm.desktop \
        "$SESSION_DIR/hyprland-uwsm.desktop"
    echo "linked hyprland-uwsm.desktop → $SESSION_DIR/"
fi

sudo mkdir -p /etc/sddm.conf.d
if [ ! -f "$SDDM_CONF" ]; then
    echo "writing SDDM session dir config: $SDDM_CONF"
    sudo tee "$SDDM_CONF" >/dev/null <<CONF
[Wayland]
SessionDir=$SESSION_DIR
CONF
else
    echo "SDDM session config already present"
fi
