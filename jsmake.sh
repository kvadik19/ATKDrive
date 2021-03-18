#! /bin/sh
home=/var/www/atk/htdocs/js
if [ $# -ne 1 ]
then
	for scr in support account query
	do
		if [ ! -f "$home/$scr.min.js" ] || [ "$home/$scr.js" -nt "$home/$scr.min.js" ]
		then
			echo "Compile ${scr}.js -> $home/$scr.min.js..."
			closure-compiler $home/$scr.js > $home/$scr.min.js
		else
			echo "File $scr.min.js looks good. Skipped."
		fi
	done
else
	echo "Compile ${home}/${1}.js..."
	closure-compiler $home/$1.js > $home/$1.min.js
fi

