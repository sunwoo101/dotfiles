#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"

if ! command -v gsettings >/dev/null 2>&1; then
    echo "gsettings not available, skipping"
    exit 0
fi

# Apply a single gsettings key. Logs a warning if the key is missing
# (e.g. running on a system without GNOME) but does NOT fail — gsettings
# returning "No such schema" shouldn't abort the install.
gset() {
    if ! gsettings set "$1" "$2" "$3" 2>/tmp/gset-err; then
        echo "warning: gsettings set $1 $2 failed: $(cat /tmp/gset-err)" >&2
    fi
    rm -f /tmp/gset-err
}

# read theme block from colors.json + override file (override wins)
read -r GTK_THEME ICON_THEME CURSOR_THEME CURSOR_SIZE <<<"$(
python3 - "$DOTFILES" <<'PY'
import json, pathlib, sys
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

# derive dark vs light from theme name
if echo "$GTK_THEME" | grep -qiE "latte|-light"; then
    SCHEME="prefer-light"
else
    SCHEME="prefer-dark"
fi
gset org.gnome.desktop.interface color-scheme  "$SCHEME"
gset org.gnome.desktop.interface gtk-theme      "$GTK_THEME"
gset org.gnome.desktop.interface icon-theme     "$ICON_THEME"
gset org.gnome.desktop.interface cursor-theme   "$CURSOR_THEME"
gset org.gnome.desktop.interface cursor-size    "$CURSOR_SIZE"
gset org.gnome.desktop.wm.preferences button-layout ':'

# also tell hyprland (so the cursor in the compositor matches GTK apps)
if command -v hyprctl >/dev/null 2>&1; then
    if ! hyprctl setcursor "$CURSOR_THEME" "$CURSOR_SIZE" 2>/tmp/hyprctl-err; then
        echo "warning: hyprctl setcursor failed (Hyprland not running?): $(cat /tmp/hyprctl-err)" >&2
    fi
    rm -f /tmp/hyprctl-err
fi

# write icon theme into qt5ct/qt6ct configs so Qt apps (incl. Quickshell)
# resolve icons via QIcon::fromTheme into the active theme
python3 - "$ICON_THEME" <<'PY'
import sys, pathlib, configparser
icon_theme = sys.argv[1]
for confdir in ("qt5ct", "qt6ct"):
    path = pathlib.Path.home() / ".config" / confdir / f"{confdir}.conf"
    path.parent.mkdir(parents=True, exist_ok=True)
    cp = configparser.ConfigParser()
    cp.optionxform = str  # preserve case
    if path.exists():
        cp.read(path)
    if not cp.has_section("Appearance"):
        cp.add_section("Appearance")
    cp.set("Appearance", "icon_theme", icon_theme)
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
PY

echo "set gsettings cursor=$CURSOR_THEME size=$CURSOR_SIZE, gtk=$GTK_THEME, icon=$ICON_THEME"
