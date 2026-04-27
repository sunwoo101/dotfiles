#!/usr/bin/env bash
set -euo pipefail

# system-level services (run before any user session)
echo "enabling system services"
sudo systemctl enable sddm.service
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service

# user-level services (started with the user session)
# UWSM handles dbus env propagation, pipewire is socket-activated; only
# enable things that need explicit autostart.
echo "enabling user services"
systemctl --user enable hyprpolkitagent.service

# populate ~/Documents, ~/Downloads, ~/Pictures, etc.
xdg-user-dirs-update
echo "xdg user dirs updated"
