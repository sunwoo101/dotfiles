#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LIST="$DOTFILES/packages/aur"

if ! command -v yay >/dev/null 2>&1; then
    echo "yay not installed; run scripts/install_yay.sh first" >&2
    exit 1
fi

if [ ! -f "$LIST" ]; then
    echo "no aur list at $LIST"
    exit 0
fi

mapfile -t PKGS < <(sed -n 's/^- //p' "$LIST")
if [ "${#PKGS[@]}" -eq 0 ]; then
    echo "no packages in $LIST"
    exit 0
fi

echo "installing ${#PKGS[@]} AUR packages"
yay -S --needed --noconfirm "${PKGS[@]}"
