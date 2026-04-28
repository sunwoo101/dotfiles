#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
DOTFILES_CONFIG="$DOTFILES/.config"

# generate per-tool config from colors.json + optional override file
OVERRIDE="${HOME}/.cache/quickshell/colors-override.json"

python3 - "$DOTFILES_CONFIG" "$DOTFILES" "$OVERRIDE" <<'PY'
import json, sys, os
base = sys.argv[1]
repo = sys.argv[2]
override_path = sys.argv[3]

data = json.load(open(os.path.join(base, "colors.json")))

# generated files live in dirs that may not exist yet on a fresh checkout
# (the dirs contain only gitignored output, so they're not tracked)
for d in ("ohmyposh", "gtk-3.0", "gtk-4.0", "bashrc"):
    os.makedirs(os.path.join(base, d), exist_ok=True)

# shallow-merge override on top: override.ui[*] beats base.ui[*], etc.
if os.path.exists(override_path):
    try:
        with open(override_path) as f:
            text = f.read().strip()
        if text:
            override = json.loads(text)
            for section, values in override.items():
                if isinstance(values, dict) and section in data:
                    data[section].update(values)
                else:
                    data[section] = values
    except (json.JSONDecodeError, OSError) as e:
        sys.stderr.write(f"warning: ignoring override ({e})\n")

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
cursor_theme = data["theme"]["cursor"]
cursor_size = data["theme"]["cursor_size"]

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

# oh-my-posh: load template (tracked, hand-edited blocks/segments) and inject
# the palette from merged colors. output is gitignored so accent clicks don't
# pollute git status.
template_path = os.path.join(repo, "templates", "ohmyposh.omp.json")
theme_out = os.path.join(base, "ohmyposh", "theme.omp.json")
theme = json.load(open(template_path))
theme["palette"] = {
    "_note": "generated — edit colors.json or palette source",
    **ui,
    **data["ansi"],   # expose p:red, p:yellow, p:green, etc. to templates
}
with open(theme_out, "w") as f:
    json.dump(theme, f, indent=2, ensure_ascii=False)
    f.write("\n")

# gtk settings.ini (3 + 4)
def settings_ini(extra=""):
    lines = [
        "[Settings]",
        f"gtk-theme-name={gtk_theme}",
        f"gtk-icon-theme-name={icon_theme}",
        f"gtk-cursor-theme-name={cursor_theme}",
        f"gtk-cursor-theme-size={cursor_size}",
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

/* one widget (the OS window) paints rgba; every other surface inside it is
   transparent so layered widgets don't compound alpha. result: uniform 0.7
   across the whole window. popovers/dialogs/accents stay opaque since they're
   either floating overlays (need readable bg) or semantic indicators (buttons). */
@define-color window_bg_color {bg_rgba};
@define-color view_bg_color transparent;
@define-color sidebar_bg_color transparent;
@define-color sidebar_backdrop_color transparent;
@define-color secondary_sidebar_bg_color transparent;
@define-color secondary_sidebar_backdrop_color transparent;
@define-color card_bg_color transparent;
@define-color headerbar_bg_color transparent;
@define-color headerbar_backdrop_color transparent;
@define-color toolbarview_top_bar_color transparent;
@define-color toolbarview_bottom_bar_color transparent;
@define-color thumbnail_bg_color transparent;

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
box.vertical headerbar,
box.vertical headerbar:backdrop,
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
gtkrc2 = f"""# generated from colors.json — do not edit
gtk-theme-name="{gtk2_theme}"
gtk-icon-theme-name="{icon_theme}"
gtk-font-name="JetBrainsMono Nerd Font 11"
gtk-cursor-theme-name="{cursor_theme}"
gtk-cursor-theme-size={cursor_size}
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
home_dir = os.path.join(repo, "home")
os.makedirs(home_dir, exist_ok=True)
with open(os.path.join(home_dir, ".gtkrc-2.0"), "w") as f:
    f.write(gtkrc2)
PY

echo "generated configs from colors.json"
