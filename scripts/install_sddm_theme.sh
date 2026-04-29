#!/usr/bin/env bash
set -euo pipefail

# Install the dotfiles SDDM greeter theme. Source lives in
# sddm-theme/dotfiles/ in the repo; SDDM reads from /usr/share/sddm/themes/.
# We copy (not symlink) so SDDM, which runs as the `sddm` user before any
# session starts, doesn't have to chase a symlink into a user homedir that
# might be on an encrypted/late-mounted filesystem.

DOTFILES="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
SRC="$DOTFILES/sddm-theme/dotfiles"
DEST=/usr/share/sddm/themes/dotfiles
SDDM_THEME_CONF=/etc/sddm.conf.d/theme.conf

if [ ! -f "$SRC/theme.conf" ]; then
    echo "ERROR: $SRC/theme.conf missing — run scripts/render_configs.sh first" >&2
    exit 1
fi

echo "installing sddm theme to $DEST"
sudo rm -rf "$DEST"
sudo mkdir -p "$DEST"
sudo cp -a "$SRC"/. "$DEST"/
sudo chown -R root:root "$DEST"

sudo mkdir -p /etc/sddm.conf.d
if [ ! -f "$SDDM_THEME_CONF" ] || ! grep -q '^Current=dotfiles$' "$SDDM_THEME_CONF"; then
    echo "writing $SDDM_THEME_CONF"
    sudo tee "$SDDM_THEME_CONF" >/dev/null <<CONF
[Theme]
Current=dotfiles
CONF
else
    echo "$SDDM_THEME_CONF already selects dotfiles"
fi
