#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
DOTFILES_CONFIG="$DOTFILES/.config"
USER_CONFIG="$HOME/.config"

mkdir -p "$USER_CONFIG"

# symlink each top-level entry in dotfiles/.config into ~/.config
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

# symlink each entry in dotfiles/home into $HOME (e.g. .gtkrc-2.0)
HOME_DIR="$DOTFILES/home"
if [ -d "$HOME_DIR" ]; then
    for src in "$HOME_DIR"/.* "$HOME_DIR"/*; do
        [ -e "$src" ] || continue
        name=$(basename "$src")
        case "$name" in . | ..) continue ;; esac
        dest="$HOME/$name"

        if [ -L "$dest" ]; then
            rm "$dest"
        elif [ -e "$dest" ]; then
            rm -rf "$dest"
        fi

        ln -s "$src" "$dest"
        echo "linked $dest -> $src"
    done
fi
