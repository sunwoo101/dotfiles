#!/usr/bin/env bash
set -euo pipefail

# Apply our pacman.conf customizations:
#   1. Enable [multilib] (lib32-* packages: mesa, vulkan, nvidia, etc.)
#   2. NoExtract paths we don't want pacman to install — currently the
#      non-UWSM Hyprland session file, since SDDM lists both
#      "Hyprland" and "Hyprland (UWSM-managed)" otherwise and we only
#      want the UWSM one.

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

# ---- NoExtract: hide the non-UWSM Hyprland session ----------------------
# SDDM scans /usr/share/wayland-sessions/*.desktop. The hyprland package
# installs hyprland.desktop and the uwsm package installs
# hyprland-uwsm.desktop. We only want the UWSM-managed entry, so
# prevent pacman from extracting the plain one on this and future
# upgrades. NoExtract uses path patterns; the leading slash is omitted
# per pacman.conf syntax.
NOEXTRACT='NoExtract = usr/share/wayland-sessions/hyprland.desktop'
if grep -Fxq "$NOEXTRACT" "$CONF"; then
    echo "NoExtract for hyprland.desktop already present"
else
    echo "adding NoExtract for hyprland.desktop to $CONF"
    # Insert immediately after the [options] header so it lands inside
    # the [options] section regardless of which other directives are
    # there.
    sudo sed -i "/^\[options\]/a $NOEXTRACT" "$CONF"
    if ! grep -Fxq "$NOEXTRACT" "$CONF"; then
        echo "ERROR: failed to add NoExtract directive — check $CONF manually" >&2
        exit 1
    fi
fi

# NoExtract only affects future extractions. If hyprland is already
# installed, the file is still present — remove it now so the change
# takes effect immediately. (Re-installing or upgrading the hyprland
# package will not recreate it because of the directive above.)
TARGET=/usr/share/wayland-sessions/hyprland.desktop
if [ -e "$TARGET" ]; then
    echo "removing existing $TARGET"
    sudo rm "$TARGET"
fi
