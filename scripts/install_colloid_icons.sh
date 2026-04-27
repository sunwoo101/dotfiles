#!/usr/bin/env bash
set -euo pipefail

# Colloid icon theme — installed from upstream (not AUR) so we get the bold
# (-b) variant which the AUR package doesn't expose.
# https://github.com/vinceliuice/Colloid-icon-theme

REPO="https://github.com/vinceliuice/Colloid-icon-theme.git"
SENTINEL="$HOME/.local/share/icons/Colloid-Dark"  # exists after first install

if [ -d "$SENTINEL" ]; then
    echo "Colloid icons already installed (found $SENTINEL); skipping"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git clone --depth=1 "$REPO" "$TMP/colloid"
cd "$TMP/colloid"

# -b = bold variant (heavier outlines). install.sh writes to ~/.local/share/icons/
./install.sh -b

# patch inheritance: upstream sets `Inherits=hicolor,breeze` but breeze isn't
# on Arch by default, so missing icons fall through to Adwaita full-color.
# inserting Papirus-Dark gives us flat fallbacks consistent with Colloid's
# style.
for variant in Colloid Colloid-Dark Colloid-Light; do
    f="$HOME/.local/share/icons/$variant/index.theme"
    [ -f "$f" ] || continue
    sed -i 's/^Inherits=.*/Inherits=Papirus-Dark,Adwaita,hicolor,breeze/' "$f"
    gtk-update-icon-cache -f "$HOME/.local/share/icons/$variant" 2>/dev/null || true
done

echo "Colloid icons installed to ~/.local/share/icons/ (inheriting Papirus-Dark)"
