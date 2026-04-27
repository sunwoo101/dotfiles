#!/usr/bin/env bash
set -euo pipefail

BASHRC="$HOME/.bashrc"
SOURCE_BLOCK='for f in "$HOME"/.config/bashrc/*; do [ -r "$f" ] && . "$f"; done'

if grep -Fqx "$SOURCE_BLOCK" "$BASHRC" 2>/dev/null; then
    echo "$BASHRC already sources dotfiles bashrc fragments"
    exit 0
fi

printf '\n# source dotfiles bashrc fragments\n%s\n' "$SOURCE_BLOCK" >> "$BASHRC"
echo "appended bashrc source block to $BASHRC"
