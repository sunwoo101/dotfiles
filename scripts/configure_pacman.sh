#!/usr/bin/env bash
set -euo pipefail

# Apply our pacman.conf customizations:
#   1. Enable [multilib] (lib32-* packages: mesa, vulkan, nvidia, etc.)
#   2. Hide hyprland.desktop from SDDM without removing it:
#      - NoExtract stops pacman writing it to wayland-sessions/ (SDDM scan path)
#      - A pacman hook extracts it from the package cache to applications/
#        (uwsm also searches there, so session launch still works)
#      - Migration: cleans up any state left by prior approaches

CONF=/etc/pacman.conf
WAYLAND_TARGET=/usr/share/wayland-sessions/hyprland.desktop
APPS_TARGET=/usr/share/applications/hyprland.desktop
SYNC_SCRIPT=/usr/local/lib/hyprland-desktop-sync.sh
HOOK_DIR=/etc/pacman.d/hooks
HOOK="$HOOK_DIR/hyprland-desktop-sync.hook"

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
if grep -q '^Hidden=true' "$WAYLAND_TARGET" 2>/dev/null; then
    echo "removing stale Hidden=true from $WAYLAND_TARGET"
    sudo sed -i '/^Hidden=true$/d' "$WAYLAND_TARGET"
fi
STALE_HOOK="$HOOK_DIR/hide-hyprland-session.hook"
if [ -f "$STALE_HOOK" ]; then
    echo "removing stale hook: $STALE_HOOK"
    sudo rm "$STALE_HOOK"
fi

# ---- NoExtract: keep hyprland.desktop out of SDDM's scan path -----------
NOEXTRACT='NoExtract = usr/share/wayland-sessions/hyprland.desktop'
if grep -Fxq "$NOEXTRACT" "$CONF"; then
    echo "NoExtract for hyprland.desktop already set"
else
    echo "adding NoExtract for hyprland.desktop to $CONF"
    sudo sed -i "/^\[options\]/a $NOEXTRACT" "$CONF"
fi

# ---- sync script ---------------------------------------------------------
sudo mkdir -p /usr/local/lib
sudo tee "$SYNC_SCRIPT" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
# Extracts hyprland.desktop from the pacman package cache into
# /usr/share/applications/ so uwsm can find it without exposing it
# in SDDM's wayland-sessions/ scan path.
pkg=$(find /var/cache/pacman/pkg -name 'hyprland-[0-9]*.pkg.tar.*' | sort -V | tail -1)
if [ -z "$pkg" ]; then
    echo "WARNING: hyprland package not in pacman cache — /usr/share/applications/hyprland.desktop not updated" >&2
    exit 0
fi
bsdtar -xOf "$pkg" usr/share/wayland-sessions/hyprland.desktop \
    > /usr/share/applications/hyprland.desktop
echo "synced hyprland.desktop → /usr/share/applications/"
SCRIPT
sudo chmod +x "$SYNC_SCRIPT"

# ---- pacman hook: re-sync after hyprland install/upgrade -----------------
sudo mkdir -p "$HOOK_DIR"
if [ ! -f "$HOOK" ]; then
    echo "installing pacman hook: $HOOK"
    sudo tee "$HOOK" >/dev/null <<HOOK
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = hyprland

[Action]
Description = Syncing Hyprland desktop entry to applications/ (out of SDDM scan path)...
When = PostTransaction
Exec = $SYNC_SCRIPT
HOOK
else
    echo "pacman hook already present"
fi

# ---- initial sync + remove from wayland-sessions/ ------------------------
echo "running initial desktop entry sync"
sudo "$SYNC_SCRIPT"
if [ -e "$WAYLAND_TARGET" ]; then
    echo "removing $WAYLAND_TARGET from SDDM scan path"
    sudo rm "$WAYLAND_TARGET"
fi
