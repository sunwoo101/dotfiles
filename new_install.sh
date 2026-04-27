#!/usr/bin/env bash
set -euo pipefail

DOTFILES_CONFIG="$HOME/dotfiles/.config"
USER_CONFIG="$HOME/.config"

# generate per-tool config from the single source of truth
python3 - "$DOTFILES_CONFIG" <<'PY'
import json, sys, os
base = sys.argv[1]
data = json.load(open(os.path.join(base, "colors.json")))

ANSI_ORDER = [
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "bright_black", "bright_red", "bright_green", "bright_yellow",
    "bright_blue", "bright_magenta", "bright_cyan", "bright_white",
]

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgba(hex_color, alpha):
    r, g, b = hex_to_rgb(hex_color)
    return f"rgba({r}, {g}, {b}, {alpha})"

ui = data["ui"]
bg_rgba = rgba(ui["bg"], data["opacity"]["bg"])
gtk_theme = data["theme"]["gtk"]
gtk2_theme = data["theme"]["gtk2_fallback"]
icon_theme = data["theme"]["icon"]

# kitty colors.conf (ANSI palette + UI colors + opacity)
with open(os.path.join(base, "colors.conf"), "w") as f:
    f.write("# generated from colors.json — do not edit\n")
    for i, name in enumerate(ANSI_ORDER):
        f.write(f"color{i:<6} {data['ansi'][name]}\n")
    f.write(f"\nbackground           {ui['bg']}\n")
    f.write(f"foreground           {ui['fg']}\n")
    f.write(f"cursor_text_color    {ui['bg']}\n")
    f.write(f"selection_foreground {ui['bg']}\n")
    f.write(f"selection_background {ui['fg']}\n")
    f.write(f"url_color            {ui['url']}\n")
    f.write(f"background_opacity   {data['opacity']['bg']}\n")

# bash exports
with open(os.path.join(base, "bashrc", "colors"), "w") as f:
    f.write("# generated from colors.json — do not edit\n")
    for k, v in ui.items():
        f.write(f"export {k.upper()}={v}\n")
    for k, v in data["opacity"].items():
        f.write(f"export {k.upper()}_OPACITY={v}\n")

# oh-my-posh palette
theme_path = os.path.join(base, "ohmyposh", "theme.omp.json")
theme = json.load(open(theme_path))
theme["palette"] = {"_note": "managed by new_install.sh — edit colors.json instead", **ui}
with open(theme_path, "w") as f:
    json.dump(theme, f, indent=2, ensure_ascii=False)
    f.write("\n")

# gtk settings.ini (3 + 4)
def settings_ini(extra=""):
    lines = [
        "[Settings]",
        f"gtk-theme-name={gtk_theme}",
        f"gtk-icon-theme-name={icon_theme}",
        "gtk-font-name=JetBrainsMono Nerd Font 11",
        "gtk-decoration-layout=:",
    ]
    if extra:
        lines.append(extra)
    return "\n".join(lines) + "\n"

with open(os.path.join(base, "gtk-3.0", "settings.ini"), "w") as f:
    f.write(settings_ini("gtk-application-prefer-dark-theme=1"))
with open(os.path.join(base, "gtk-4.0", "settings.ini"), "w") as f:
    f.write(settings_ini())

# gtk.css — gtk-3.0. simpler than gtk-4.0: most GTK3 apps have a flat
# widget tree (window + .background on the same toplevel), so painting
# both with rgba doesn't compound.
gtk3_css = f"""/* generated from colors.json — do not edit */
window,
window.csd,
window.background,
window.background:backdrop,
window.csd.background,
dialog,
dialog.background,
.background,
.background:backdrop,
GtkWindow {{
    background-color: {bg_rgba};
}}
"""
with open(os.path.join(base, "gtk-3.0", "gtk.css"), "w") as f:
    f.write(gtk3_css)

# gtk-4.0 — libadwaita ignores gtk-theme-name, must @import the theme here
theme_gtk4 = f"/usr/share/themes/{gtk_theme}/gtk-4.0/gtk.css"
gtk4_css = f"""/* generated from colors.json — do not edit */
@import url("file://{theme_gtk4}");

/* one widget (the OS window) paints rgba; every other surface is fully
   transparent so multiple layers don't compound alpha. result: uniform 0.7
   across sidebar, main content, headerbar — no darker patches in deeper areas. */
@define-color window_bg_color {bg_rgba};
@define-color view_bg_color transparent;
@define-color sidebar_bg_color transparent;
@define-color card_bg_color transparent;
@define-color headerbar_bg_color transparent;

window,
window:backdrop,
window.csd,
window.csd:backdrop,
window.background,
window.background:backdrop,
window.csd.background,
window.csd.background:backdrop {{
    background-color: {bg_rgba};
}}

.background,
.background:backdrop,
.sidebar,
.sidebar:backdrop,
.sidebar-pane,
.sidebar-pane:backdrop,
.navigation-sidebar,
.navigation-sidebar:backdrop,
.navigation-sidebar.background,
.navigation-sidebar.background:backdrop,
placessidebar,
placessidebar:backdrop,
.view,
.view:backdrop,
statuspage,
statuspage:backdrop,
.empty-state,
.empty-state:backdrop,
headerbar,
headerbar:backdrop,
.titlebar,
.titlebar:backdrop,
.nautilus-window,
.nautilus-window:backdrop,
notebook,
notebook:backdrop,
notebook header,
notebook header:backdrop,
notebook stack,
notebook stack:backdrop,
frame,
frame:backdrop,
frame > border,
viewport,
viewport:backdrop,
scrolledwindow,
scrolledwindow:backdrop,
listbox,
listbox:backdrop,
paned > separator {{
    background-color: transparent;
}}

"""
with open(os.path.join(base, "gtk-4.0", "gtk.css"), "w") as f:
    f.write(gtk4_css)

# gtkrc-2.0 — catppuccin doesn't ship a GTK2 theme, so use Adwaita fallback
# but otherwise mirror our other GTK theme settings so old GTK2 apps look reasonable.
gtkrc2 = f"""# generated from colors.json — do not edit
gtk-theme-name="{gtk2_theme}"
gtk-icon-theme-name="{icon_theme}"
gtk-font-name="JetBrainsMono Nerd Font 11"
gtk-cursor-theme-name="default"
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=0
gtk-menu-images=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle="hintslight"
gtk-xft-rgba="rgb"
"""
home_dir = os.path.join(os.path.dirname(base.rstrip("/")), "home")
os.makedirs(home_dir, exist_ok=True)
with open(os.path.join(home_dir, ".gtkrc-2.0"), "w") as f:
    f.write(gtkrc2)
PY
echo "generated configs from colors.json"

mkdir -p "$USER_CONFIG"

for src in "$DOTFILES_CONFIG"/*; do
    [ -e "$src" ] || continue
    name=$(basename "$src")
    dest="$USER_CONFIG/$name"

    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        rm -rf "$dest"
    fi

    ln -s "$src" "$dest"
    echo "linked $dest -> $src"
done

# symlink ~/.gtkrc-2.0 -> dotfiles/home/.gtkrc-2.0 (GTK2 settings live in $HOME, not .config)
GTKRC2_SRC="$HOME/dotfiles/home/.gtkrc-2.0"
GTKRC2_DEST="$HOME/.gtkrc-2.0"
if [ -L "$GTKRC2_DEST" ]; then
    rm "$GTKRC2_DEST"
elif [ -e "$GTKRC2_DEST" ]; then
    rm -rf "$GTKRC2_DEST"
fi
ln -s "$GTKRC2_SRC" "$GTKRC2_DEST"
echo "linked $GTKRC2_DEST -> $GTKRC2_SRC"

# prefer dark + set gtk theme from colors.json
if command -v gsettings >/dev/null 2>&1; then
    GTK_THEME=$(python3 -c "import json; print(json.load(open('$DOTFILES_CONFIG/colors.json'))['theme']['gtk'])")
    ICON_THEME=$(python3 -c "import json; print(json.load(open('$DOTFILES_CONFIG/colors.json'))['theme']['icon'])")
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
    gsettings set org.gnome.desktop.wm.preferences button-layout ':' || true
    echo "set gsettings color-scheme=prefer-dark, gtk-theme=$GTK_THEME, icon-theme=$ICON_THEME, button-layout=:"
fi

BASHRC="$HOME/.bashrc"
SOURCE_BLOCK='for f in "$HOME"/.config/bashrc/*; do [ -r "$f" ] && . "$f"; done'
if ! grep -Fqx "$SOURCE_BLOCK" "$BASHRC" 2>/dev/null; then
    printf '\n# source dotfiles bashrc fragments\n%s\n' "$SOURCE_BLOCK" >> "$BASHRC"
    echo "appended bashrc source block to $BASHRC"
fi
