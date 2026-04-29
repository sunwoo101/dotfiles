#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LIST="$DOTFILES/packages/pacman-arm"

if [ ! -f "$LIST" ]; then
    echo "ERROR: ARM pacman list missing at $LIST" >&2
    exit 1
fi

mapfile -t PKGS < <(sed -n 's/^- //p' "$LIST")
if [ "${#PKGS[@]}" -eq 0 ]; then
    echo "ERROR: ARM pacman list at $LIST is empty" >&2
    exit 1
fi

echo "installing ${#PKGS[@]} pacman packages"
sudo pacman -Syu --needed --noconfirm --overwrite "*" "${PKGS[@]}"
