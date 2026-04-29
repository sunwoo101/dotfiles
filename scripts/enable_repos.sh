#!/usr/bin/env bash
set -euo pipefail

# Enable optional pacman repositories that some packages in the lists need.
# Currently: multilib (for lib32-* packages — mesa, vulkan, nvidia, etc.)

CONF=/etc/pacman.conf

# Active (uncommented) [multilib] block already in place — nothing to do.
if grep -Pzq '(?s)^\[multilib\]\s*\nInclude\s*=' "$CONF"; then
    echo "[multilib] already enabled"
    exit 0
fi

if ! grep -q '^\s*#\s*\[multilib\]' "$CONF"; then
    echo "ERROR: $CONF has no [multilib] section to uncomment" >&2
    exit 1
fi

echo "enabling [multilib] in $CONF"
# Address-range sed: from the commented [multilib] line through the next
# Include line, strip leading `#` from each. Tolerant of blank/comment
# lines between, unlike the previous `n;s/^#//` chain.
sudo sed -i -E '/^\s*#\s*\[multilib\]/,/^\s*#\s*Include\s*=/{ s/^#// }' "$CONF"

# Verify the edit landed.
if ! grep -Pzq '(?s)^\[multilib\]\s*\nInclude\s*=' "$CONF"; then
    echo "ERROR: failed to uncomment [multilib] in $CONF — check it manually" >&2
    exit 1
fi

sudo pacman -Sy
echo "[multilib] enabled"
