#!/usr/bin/env bash
set -euo pipefail

# ARM: Arch Linux ARM has no [multilib] repo — skip that step entirely.
# Install a pacman hook that patches Hidden=true into hyprland.desktop
# after install/upgrade so SDDM only shows the UWSM-managed entry.
# The file is kept on disk — uwsm references it as the compositor entry.

CONF=/etc/pacman.conf

# Migrate: remove stale NoExtract directive if a prior run added it.
sudo sed -i '/^NoExtract.*hyprland\.desktop/d' "$CONF"

# Restore the file if a prior run deleted it.
TARGET=/usr/share/wayland-sessions/hyprland.desktop
if [ ! -e "$TARGET" ]; then
    echo "restoring missing $TARGET (reinstalling hyprland)"
    sudo pacman -S --noconfirm --overwrite "*" hyprland
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
