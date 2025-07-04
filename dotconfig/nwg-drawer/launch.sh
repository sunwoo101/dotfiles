style="glow.css"
nwg-drawer -mb 8 -ml 8 -mr 8 -mt 8 -ovl -closebtn right -nocats -nofs -open \
-pblock '~/.config/hypr/scripts/power.sh lock' \
-pbpoweroff '~/.config/hypr/scripts/power.sh shutdown' \
-pbreboot '~/.config/hypr/scripts/power.sh reboot' \
-pbsleep '~/.config/hypr/scripts/power.sh suspend' \
-s $style
