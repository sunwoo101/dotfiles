#!/usr/bin/env bash
set -euo pipefail

# Enable optional pacman repositories that some packages in the lists need.
# Currently: multilib (for lib32-* packages — mesa, vulkan, nvidia, etc.)

CONF=/etc/pacman.conf

# Find the line number of an uncommented `[multilib]` (if any).
ACTIVE_HEADER=$(grep -nE '^\[multilib\]\s*$' "$CONF" | head -1 | cut -d: -f1)

if [ -n "$ACTIVE_HEADER" ]; then
    # Verify the next non-empty, non-comment line is an Include directive
    # — otherwise the block is half-edited and we should still uncomment.
    NEXT=$(awk -v start="$ACTIVE_HEADER" 'NR > start && NF > 0 && $1 !~ /^#/ {print; exit}' "$CONF")
    if echo "$NEXT" | grep -q '^Include'; then
        echo "[multilib] already enabled"
        exit 0
    fi
fi

# Otherwise look for a commented `#[multilib]` block to uncomment.
if ! grep -qE '^\s*#\s*\[multilib\]' "$CONF"; then
    echo "ERROR: $CONF has no [multilib] section to enable" >&2
    exit 1
fi

echo "enabling [multilib] in $CONF"
# Address-range sed: from the commented [multilib] line through the next
# Include line, strip leading `#` from each. Tolerant of blank/comment
# lines between, unlike the previous `n;s/^#//` chain.
sudo sed -i -E '/^\s*#\s*\[multilib\]/,/^\s*#\s*Include\s*=/{ s/^#// }' "$CONF"

# Verify the edit landed.
if ! grep -qE '^\[multilib\]\s*$' "$CONF"; then
    echo "ERROR: failed to uncomment [multilib] in $CONF — check it manually" >&2
    exit 1
fi

sudo pacman -Sy
echo "[multilib] enabled"
