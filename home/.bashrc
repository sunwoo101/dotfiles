for f in ~/.config/bashrc/*; do
	if [ ! -d $f ]; then
		c=`echo $f | sed -e "s=.config/bashrc=.config/bashrc/custom="`
		[[ -f $c ]] && source $c || source $f
	fi
done

if [ -f ~/.bashrc_custom ]; then
	source ~/.bashrc_custom
fi
