#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
SCRIPTS="$DIR/scripts"

run() {
    echo
    echo "=== $1 ==="
    "$SCRIPTS/$1"
}

run install_pacman_packages.sh
run install_gpu_drivers.sh
run install_yay.sh
run install_aur_packages.sh
run enable_services.sh
run render_configs.sh
run symlink_dotfiles.sh
run apply_gsettings.sh
run hook_bashrc.sh

echo
echo "all done."
