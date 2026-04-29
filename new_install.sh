#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
SCRIPTS="$DIR/scripts"

# Defensive: make sure scripts are executable even if the bit was lost
# during a tarball extraction / non-preserving copy / etc.
chmod +x "$SCRIPTS"/*.sh

# Track the script that's currently running so the ERR trap can name it.
CURRENT_SCRIPT=""
trap 'rc=$?; echo; echo "=== FAILED in: ${CURRENT_SCRIPT:-<setup>} (exit $rc) ===" >&2; exit $rc' ERR

# Cache sudo credentials once and keep them alive in the background. Without
# this, a long install (pacman + AUR + yay bootstrap) would prompt for the
# password 4–5 times as the cached credential expires (~5 min default).
echo "Caching sudo credentials..."
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

run() {
    CURRENT_SCRIPT=$1
    echo
    echo "=== $1 ==="
    "$SCRIPTS/$1"
}

run configure_pacman.sh
run install_pacman_packages.sh
run install_gpu_drivers.sh
run install_yay.sh
run install_aur_packages.sh
run install_colloid_icons.sh
run enable_services.sh
run render_configs.sh
run symlink_dotfiles.sh
run apply_gsettings.sh
run hook_bashrc.sh

CURRENT_SCRIPT=""
echo
echo "all done."
