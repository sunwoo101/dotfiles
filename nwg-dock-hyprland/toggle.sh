#!/bin/bash

if pgrep -f "nwg-dock-hyprland" > /dev/null; then
	killall nwg-dock-hyprland
else
	~/.config/nwg-dock-hyprland/launch.sh
fi
