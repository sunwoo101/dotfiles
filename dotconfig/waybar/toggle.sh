#!/bin/bash

if pidof "waybar" > /dev/null; then
	killall waybar
else
	~/.config/waybar/launch.sh
fi
