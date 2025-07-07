style="glow.css"
killall nwg-drawer
nwg-drawer -mb 8 -ml 8 -mr 8 -mt 8 -ovl -closebtn right -nocats -nofs -open \
-pblock "sh $HOME/.config/hypr/scripts/power.sh lock" \
-pbpoweroff "sh $HOME/.config/hypr/scripts/power.sh shutdown" \
-pbreboot "sh $HOME/.config/hypr/scripts/power.sh reboot" \
-pbsleep "sh $HOME/.config/hypr/scripts/power.sh suspend" \
-s $style
