#!/usr/bin/env bash
set -euo pipefail

if command -v yay >/dev/null 2>&1; then
    echo "yay already installed: $(yay --version | head -1)"
    exit 0
fi

# yay-bin needs git + base-devel; pacman list already includes them
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$TMP/yay-bin"
cd "$TMP/yay-bin"
makepkg -si --noconfirm

echo "yay installed: $(yay --version | head -1)"
