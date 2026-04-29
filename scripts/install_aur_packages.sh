#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LIST="$DOTFILES/packages/aur"

if ! command -v yay >/dev/null 2>&1; then
    echo "ERROR: yay not installed; run scripts/install_yay.sh first" >&2
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

# --noconfirm answers all yay prompts. --mflags --skippgpcheck skips PGP
# signature verification on AUR sources — without this the install pauses
# at "Import?" for any package whose maintainer key isn't already in the
# keyring (caelestia, hyprland-git, etc.). Tradeoff: less safe, but
# unattended. --answerclean N / --answerdiff N skip the "view PKGBUILD?"
# and "view diff?" prompts.
echo "installing ${#PKGS[@]} AUR packages"
yay -S --needed --noconfirm \
    --answerclean N --answerdiff N --answeredit N \
    --mflags --skippgpcheck \
    --overwrite "*" \
    "${PKGS[@]}"
