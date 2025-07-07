#!/bin/bash

if pidof "nwg-dock-hyprland" > /dev/null; then
	killall nwg-dock-hyprland
else
	~/.config/nwg-dock-hyprland/launch.sh
fi
