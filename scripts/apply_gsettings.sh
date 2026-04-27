#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"

if ! command -v gsettings >/dev/null 2>&1; then
    echo "gsettings not available, skipping"
    exit 0
fi

# read theme block from colors.json + override file (override wins)
read -r GTK_THEME ICON_THEME CURSOR_THEME CURSOR_SIZE <<<"$(
python3 - "$DOTFILES" <<'PY'
import json, os, pathlib, sys
base = json.load(open(sys.argv[1] + "/.config/colors.json"))
override = pathlib.Path.home() / ".cache" / "quickshell" / "colors-override.json"
if override.exists():
    text = override.read_text().strip()
    if text:
        try:
            data = json.loads(text)
            for section, values in data.items():
                if isinstance(values, dict) and section in base:
                    base[section].update(values)
                else:
                    base[section] = values
        except json.JSONDecodeError:
            pass
t = base["theme"]
print(t["gtk"], t["icon"], t["cursor"], t["cursor_size"])
PY
)"

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
