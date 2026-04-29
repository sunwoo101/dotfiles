#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
DOTFILES_CONFIG="$DOTFILES/.config"
USER_CONFIG="$HOME/.config"

mkdir -p "$USER_CONFIG"

# Replaces $dest with a symlink to $src. Logs whatever's being clobbered so
# a destructive overwrite is visible, not silent.
relink() {
    local dest=$1 src=$2
    if [ -L "$dest" ]; then
        local current
        current=$(readlink "$dest")
        if [ "$current" = "$src" ]; then
            echo "  ok   $dest -> $src"
            return
        fi
        echo "  relink $dest (was -> $current, now -> $src)"
        rm "$dest"
    elif [ -e "$dest" ]; then
        echo "  REMOVE existing $dest (replacing with symlink to $src)"
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
    echo "  link $dest -> $src"
}

# ensure ~/dotfiles points at the repo. Several scripts and the Quickshell
# config reference ~/dotfiles directly (e.g. shell.qml's apply_palette.py
# invocation), so the repo must be reachable at that path regardless of
# where it's actually checked out.
if [ "$DOTFILES" != "$HOME/dotfiles" ]; then
    if [ -L "$HOME/dotfiles" ] || [ ! -e "$HOME/dotfiles" ]; then
        if [ -L "$HOME/dotfiles" ]; then rm "$HOME/dotfiles"; fi
        ln -s "$DOTFILES" "$HOME/dotfiles"
        echo "  link $HOME/dotfiles -> $DOTFILES"
    else
        echo "  WARNING: $HOME/dotfiles exists and is not a symlink — leaving alone" >&2
    fi
fi

# symlink each top-level entry in dotfiles/.config into ~/.config
echo "linking $DOTFILES_CONFIG/* into $USER_CONFIG/"
for src in "$DOTFILES_CONFIG"/*; do
    [ -e "$src" ] || continue
    relink "$USER_CONFIG/$(basename "$src")" "$src"
done

# symlink each entry in dotfiles/home into $HOME (e.g. .gtkrc-2.0)
HOME_DIR="$DOTFILES/home"
if [ -d "$HOME_DIR" ]; then
    echo "linking $HOME_DIR/* into $HOME/"
    for src in "$HOME_DIR"/.* "$HOME_DIR"/*; do
        [ -e "$src" ] || continue
        local_name=$(basename "$src")
        case "$local_name" in . | ..) continue ;; esac
        relink "$HOME/$local_name" "$src"
    done
fi
