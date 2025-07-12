style="glass.css"
#nwg-dock-hyprland -m -hd 0 -i 18 -w 6 -mt 0 -mb 8 -ml 8 -mr 8 -x -s $style -c "sh $HOME/.config/nwg-drawer/launch.sh" -nolauncher

# multiple monitor example
nwg-dock-hyprland -o DP-3 -m -hd 0 -i 18 -w 6 -mt 0 -mb 8 -ml 8 -mr 8 -x -s $style -c "sh $HOME/.config/nwg-drawer/launch.sh" -nolauncher &
nwg-dock-hyprland -o HDMI-A-1 -m -hd 0 -i 18 -w 6 -mt 0 -mb 8 -ml 8 -mr 8 -x -s $style -c "sh $HOME/.config/nwg-drawer/launch.sh" -nolauncher
