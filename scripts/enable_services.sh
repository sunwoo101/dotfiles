#!/usr/bin/env bash
set -euo pipefail

# system-level services (run before any user session)
echo "enabling system services"
sudo systemctl enable sddm.service
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service

# user-level services. daemon-reload first so freshly-installed unit
# files (e.g. hyprpolkitagent.service) are visible to the user manager
# before we try to enable them; without this, enable can fail with
# "unit not found" on a clean install.
echo "reloading user systemd manager"
systemctl --user daemon-reload

echo "enabling user services"
systemctl --user enable hyprpolkitagent.service

# populate ~/Documents, ~/Downloads, ~/Pictures, etc.
echo "updating xdg user dirs"
xdg-user-dirs-update
