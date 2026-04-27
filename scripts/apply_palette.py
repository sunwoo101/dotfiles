#!/usr/bin/env python3
"""Write ~/.cache/quickshell/colors-override.json with a Catppuccin
flavor + accent combination.

Usage:
    apply_palette.py FLAVOR ACCENT_NAME ACCENT_HEX

FLAVOR        — "mocha" or "latte"
ACCENT_NAME   — e.g. "mauve", "pink", "blue" (the catppuccin slot name)
ACCENT_HEX    — "#cba6f7" (the accent color hex; same value across flavors)

The override is rebuilt fresh each call (no merging of stale fields). Override
contains: theme.{gtk,cursor}, ui.{bg,mantle,fg,primary,accent,url,muted,border},
ansi.* (full 16-color palette flipped to match the flavor).
"""
import json
import pathlib
import sys

OVERRIDE = pathlib.Path.home() / ".cache" / "quickshell" / "colors-override.json"

# Catppuccin canonical ANSI palettes (16 slots) per flavor. Stable; only flips
# with full flavor change.
ANSI = {
    "mocha": {
        "black":          "#45475a", "red":            "#f38ba8",
        "green":          "#a6e3a1", "yellow":         "#f9e2af",
        "blue":           "#89b4fa", "magenta":        "#f5c2e7",
        "cyan":           "#94e2d5", "white":          "#bac2de",
        "bright_black":   "#585b70", "bright_red":     "#f38ba8",
        "bright_green":   "#a6e3a1", "bright_yellow":  "#f9e2af",
        "bright_blue":    "#89b4fa", "bright_magenta": "#f5c2e7",
        "bright_cyan":    "#94e2d5", "bright_white":   "#a6adc8",
    },
    "latte": {
        "black":          "#5c5f77", "red":            "#d20f39",
        "green":          "#40a02b", "yellow":         "#df8e1d",
        "blue":           "#1e66f5", "magenta":        "#ea76cb",
        "cyan":           "#179299", "white":          "#acb0be",
        "bright_black":   "#6c6f85", "bright_red":     "#d20f39",
        "bright_green":   "#40a02b", "bright_yellow":  "#df8e1d",
        "bright_blue":    "#1e66f5", "bright_magenta": "#ea76cb",
        "bright_cyan":    "#179299", "bright_white":   "#bcc0cc",
    },
}

# Foreground (text) color — stable per flavor, doesn't follow accent.
FG = {
    "mocha": "#cdd6f4",  # Catppuccin Mocha Text
    "latte": "#4c4f69",  # Catppuccin Latte Text
}


def parse_hex(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def fmt_hex(rgb: tuple[int, int, int]) -> str:
    r, g, b = rgb
    return f"#{r:02x}{g:02x}{b:02x}"


def dark_tint(hex_str: str, f: float) -> str:
    """Mix accent toward black. f=0 black, f=1 accent."""
    r, g, b = parse_hex(hex_str)
    return fmt_hex((int(r * f), int(g * f), int(b * f)))


def light_tint(hex_str: str, f: float) -> str:
    """Mix accent toward white. f=0 white, f=1 accent."""
    r, g, b = parse_hex(hex_str)
    mix = lambda c: int(f * c + (1 - f) * 255)
    return fmt_hex((mix(r), mix(g), mix(b)))


def build_palette(flavor: str, accent_name: str, accent_hex: str) -> dict:
    if flavor == "mocha":
        ui = {
            "bg":      dark_tint(accent_hex, 0.13),
            "mantle":  dark_tint(accent_hex, 0.10),
            "fg":      FG["mocha"],
            "primary": accent_hex,
            "accent":  accent_hex,
            "url":     accent_hex,
            "muted":   dark_tint(accent_hex, 0.40),
            "border":  dark_tint(accent_hex, 0.28),
        }
    elif flavor == "latte":
        ui = {
            "bg":      light_tint(accent_hex, 0.05),
            "mantle":  light_tint(accent_hex, 0.10),
            "fg":      FG["latte"],
            "primary": accent_hex,
            "accent":  accent_hex,
            "url":     accent_hex,
            "muted":   light_tint(accent_hex, 0.55),  # darker = more visible on light bg
            "border":  light_tint(accent_hex, 0.70),
        }
    else:
        raise ValueError(f"unknown flavor: {flavor}")

    return {
        "theme": {
            "gtk":    f"catppuccin-{flavor}-{accent_name}-standard+default",
            "cursor": f"catppuccin-{flavor}-{accent_name}-cursors",
        },
        "ui":   ui,
        "ansi": ANSI[flavor],
    }


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__)
        return 2

    flavor, accent_name, accent_hex = sys.argv[1], sys.argv[2], sys.argv[3]

    if flavor not in ANSI:
        sys.stderr.write(f"unknown flavor: {flavor} (expected mocha or latte)\n")
        return 2

    palette = build_palette(flavor, accent_name, accent_hex)

    OVERRIDE.parent.mkdir(parents=True, exist_ok=True)
    OVERRIDE.write_text(json.dumps(palette, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
