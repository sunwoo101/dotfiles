#!/usr/bin/env bash
set -euo pipefail

if command -v yay >/dev/null 2>&1; then
    echo "yay already installed: $(yay --version | head -1)"
    exit 0
fi

# yay-bin needs git + base-devel (already in the pacman list)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$TMP/yay-bin"
cd "$TMP/yay-bin"
# --skippgpcheck skips signature import prompts on yay-bin's own PGP-
# signed sources (the upstream key may not be in our keyring). --noconfirm
# auto-accepts the dependency install via sudo pacman -U.
makepkg -si --noconfirm --skippgpcheck

echo "yay installed: $(yay --version | head -1)"
