#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"

if ! command -v gsettings >/dev/null 2>&1; then
    echo "gsettings not available, skipping"
    exit 0
fi

GTK_THEME=$(python3 -c "import json; print(json.load(open('$DOTFILES/.config/colors.json'))['theme']['gtk'])")
ICON_THEME=$(python3 -c "import json; print(json.load(open('$DOTFILES/.config/colors.json'))['theme']['icon'])")
CURSOR_THEME=$(python3 -c "import json; print(json.load(open('$DOTFILES/.config/colors.json'))['theme']['cursor'])")
CURSOR_SIZE=$(python3 -c "import json; print(json.load(open('$DOTFILES/.config/colors.json'))['theme']['cursor_size'])")

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" || true
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" || true
gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" || true
gsettings set org.gnome.desktop.wm.preferences button-layout ':' || true

# also tell hyprland (so the cursor in the compositor matches GTK apps)
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl setcursor "$CURSOR_THEME" "$CURSOR_SIZE" || true
fi

echo "set gsettings cursor=$CURSOR_THEME size=$CURSOR_SIZE, gtk=$GTK_THEME, icon=$ICON_THEME"
