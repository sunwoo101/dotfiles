#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LIST="$DOTFILES/packages/pacman"

if [ ! -f "$LIST" ]; then
    echo "no pacman list at $LIST"
    exit 0
fi

mapfile -t PKGS < <(sed -n 's/^- //p' "$LIST")
if [ "${#PKGS[@]}" -eq 0 ]; then
    echo "no packages in $LIST"
    exit 0
fi

echo "installing ${#PKGS[@]} pacman packages"
sudo pacman -S --needed --noconfirm "${PKGS[@]}"
