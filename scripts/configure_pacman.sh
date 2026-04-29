#!/usr/bin/env bash
set -euo pipefail

# Apply our pacman.conf customizations:
#   1. Enable [multilib] (lib32-* packages: mesa, vulkan, nvidia, etc.)
#   2. Hide hyprland.desktop from SDDM by pointing SDDM at a custom session
#      dir (/usr/local/share/wayland-sessions/) that only contains
#      hyprland-uwsm.desktop. hyprland.desktop stays in
#      /usr/share/wayland-sessions/ where uwsm finds it.

CONF=/etc/pacman.conf
SESSION_DIR=/usr/local/share/wayland-sessions
SDDM_CONF=/etc/sddm.conf.d/sessions.conf

# ---- multilib ------------------------------------------------------------
ACTIVE_HEADER=$(grep -nE '^\[multilib\]\s*$' "$CONF" | head -1 | cut -d: -f1)
MULTILIB_ALREADY=0
if [ -n "$ACTIVE_HEADER" ]; then
    NEXT=$(awk -v start="$ACTIVE_HEADER" 'NR > start && NF > 0 && $1 !~ /^#/ {print; exit}' "$CONF")
    if echo "$NEXT" | grep -q '^Include'; then
        echo "[multilib] already enabled"
        MULTILIB_ALREADY=1
    fi
fi

if [ "$MULTILIB_ALREADY" -eq 0 ]; then
    if ! grep -qE '^\s*#\s*\[multilib\]' "$CONF"; then
        echo "ERROR: $CONF has no [multilib] section to enable" >&2
        exit 1
    fi
    echo "enabling [multilib] in $CONF"
    sudo sed -i -E '/^\s*#\s*\[multilib\]/,/^\s*#\s*Include\s*=/{ s/^#// }' "$CONF"
    if ! grep -qE '^\[multilib\]\s*$' "$CONF"; then
        echo "ERROR: failed to uncomment [multilib] in $CONF — check it manually" >&2
        exit 1
    fi
    sudo pacman -Sy
    echo "[multilib] enabled"
fi

# ---- migrate stale state from prior script versions ----------------------
sudo sed -i '/^NoExtract.*hyprland\.desktop/d' "$CONF"
if [ ! -e /usr/share/wayland-sessions/hyprland.desktop ]; then
    echo "restoring missing hyprland.desktop (reinstalling hyprland)"
    sudo pacman -S --noconfirm --overwrite "*" hyprland
fi
for f in \
    /etc/pacman.d/hooks/hide-hyprland-session.hook \
    /etc/pacman.d/hooks/hyprland-desktop-sync.hook \
    /usr/local/lib/hyprland-desktop-sync.sh
do
    [ -f "$f" ] && sudo rm "$f" && echo "removed stale: $f"
done
[ -f "$SESSION_DIR/hyprland.desktop" ] && sudo rm "$SESSION_DIR/hyprland.desktop"

# ---- custom SDDM session dir ---------------------------------------------
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
