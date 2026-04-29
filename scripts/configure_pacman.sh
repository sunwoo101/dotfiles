#!/usr/bin/env bash
set -euo pipefail

# Apply our pacman.conf customizations:
#   1. Enable [multilib] (lib32-* packages: mesa, vulkan, nvidia, etc.)
#   2. Install a pacman hook that patches Hidden=true into hyprland.desktop
#      after install/upgrade so SDDM only shows the UWSM-managed entry.
#      The file is kept on disk — uwsm references it as the compositor
#      entry when launching the session via hyprland-uwsm.desktop.

CONF=/etc/pacman.conf

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
    # Address-range sed: from the commented [multilib] line through the
    # next Include line, strip leading `#` from each. Tolerant of
    # blank/comment lines between, unlike a `n;s/^#//` chain.
    sudo sed -i -E '/^\s*#\s*\[multilib\]/,/^\s*#\s*Include\s*=/{ s/^#// }' "$CONF"
    if ! grep -qE '^\[multilib\]\s*$' "$CONF"; then
        echo "ERROR: failed to uncomment [multilib] in $CONF — check it manually" >&2
        exit 1
    fi
    sudo pacman -Sy
    echo "[multilib] enabled"
fi

# ---- hide plain Hyprland session from SDDM via pacman hook ---------------
# Migrate: remove stale NoExtract directive if a prior run added it.
if grep -Fxq 'NoExtract = usr/share/wayland-sessions/hyprland.desktop' "$CONF"; then
    echo "removing stale NoExtract for hyprland.desktop from $CONF"
    sudo sed -i '/^NoExtract = usr\/share\/wayland-sessions\/hyprland\.desktop$/d' "$CONF"
fi

# Restore the file if a prior run deleted it.
TARGET=/usr/share/wayland-sessions/hyprland.desktop
if [ ! -e "$TARGET" ]; then
    echo "restoring missing $TARGET (reinstalling hyprland)"
    sudo pacman -S --needed --noconfirm --overwrite "*" hyprland
fi

# Install pacman hook so Hidden=true is reapplied after future upgrades.
HOOK_DIR=/etc/pacman.d/hooks
HOOK="$HOOK_DIR/hide-hyprland-session.hook"
sudo mkdir -p "$HOOK_DIR"
if [ ! -f "$HOOK" ]; then
    echo "installing pacman hook: $HOOK"
    sudo tee "$HOOK" >/dev/null <<'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/share/wayland-sessions/hyprland.desktop

[Action]
Description = Hiding plain Hyprland session from SDDM (use Hyprland UWSM instead)...
When = PostTransaction
Exec = /bin/sh -c "grep -q '^Hidden=true' /usr/share/wayland-sessions/hyprland.desktop 2>/dev/null || sed -i '/^\[Desktop Entry\]/a Hidden=true' /usr/share/wayland-sessions/hyprland.desktop"
HOOK
    echo "hook installed"
else
    echo "pacman hook already present"
fi

# Apply now — the hook only fires on future installs/upgrades.
if ! grep -q '^Hidden=true' "$TARGET" 2>/dev/null; then
    echo "patching $TARGET: adding Hidden=true"
    sudo sed -i '/^\[Desktop Entry\]/a Hidden=true' "$TARGET"
fi
