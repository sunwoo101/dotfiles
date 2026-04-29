#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LIST="$DOTFILES/packages/pacman"

if [ ! -f "$LIST" ]; then
    echo "ERROR: pacman list missing at $LIST" >&2
    exit 1
fi

mapfile -t PKGS < <(sed -n 's/^- //p' "$LIST")
if [ "${#PKGS[@]}" -eq 0 ]; then
    echo "ERROR: pacman list at $LIST is empty" >&2
    exit 1
fi

# Full sync+upgrade with the package list. --noconfirm answers all prompts
# with the default. --overwrite "*" lets a package take over a file that
# was previously installed by something else (rare but blocks unattended
# installs when it happens, e.g. theme overlap).
echo "installing ${#PKGS[@]} pacman packages"
sudo pacman -Syu --needed --noconfirm --overwrite "*" "${PKGS[@]}"
