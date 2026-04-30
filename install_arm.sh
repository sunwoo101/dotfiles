#!/usr/bin/env bash
set -euo pipefail

# install_arm.sh — targets Arch Linux ARM (aarch64).
# Differences from the x86_64 script:
#   - configure_pacman_arm.sh  : NoExtract only; no [multilib] (doesn't exist on ALARM)
#   - install_pacman_packages_arm.sh : reads packages/pacman-arm (no lib32-*, discord, spotify-launcher)
#   - install_gpu_drivers_arm.sh : informational only; Mesa covers open-source ARM GPUs
#   - no install_yay.sh / install_aur_packages.sh : AUR is unsupported on ALARM
#
# Note: packages/pacman-arm uses linux-aarch64-headers. If your board runs a
# different ALARM kernel (e.g. linux-rpi), replace that entry before running.

DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
SCRIPTS="$DIR/scripts"

chmod +x "$SCRIPTS"/*.sh

CURRENT_SCRIPT=""
trap 'rc=$?; echo; echo "=== FAILED in: ${CURRENT_SCRIPT:-<setup>} (exit $rc) ===" >&2; exit $rc' ERR

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

run configure_pacman_arm.sh
run install_pacman_packages_arm.sh
run install_gpu_drivers_arm.sh
run install_colloid_icons.sh
run render_configs.sh
run install_sddm_theme.sh
run symlink_dotfiles.sh
run enable_services.sh
run apply_gsettings.sh
run hook_bashrc.sh

CURRENT_SCRIPT=""
echo
echo "all done."
