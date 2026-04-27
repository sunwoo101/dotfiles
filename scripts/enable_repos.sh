#!/usr/bin/env bash
set -euo pipefail

# Enable optional pacman repositories that some packages in the lists need.
# Currently: multilib (for lib32-* packages — mesa, vulkan, nvidia, etc.)

CONF=/etc/pacman.conf

if grep -q "^\[multilib\]" "$CONF"; then
    echo "multilib already enabled"
else
    echo "enabling [multilib] in $CONF"
    # Uncomment the [multilib] block — header line + the Include line below it
    sudo sed -i '/^#\s*\[multilib\]/{s/^#\s*//; n; s/^#\s*//}' "$CONF"
    sudo pacman -Sy
fi
