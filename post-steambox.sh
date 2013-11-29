#!/bin/bash

if [[ -f `pwd`/post-shared.sh ]]; then
	source post-shared.sh
else
	echo "missing file: shared-functions.sh"
	exit 1
fi

check_notroot
check_whiptail

enable_ssh

install_aur_helper
install_multilib_repo
install_xorg
install_video_drivers
install_xbmc
install_fonts
install_grub_holdshift

sudo pacman -S steam xterm
sudo pacman -S wmctrl

#disable_root_login

# add xbmc menu item?
# <onclick>XBMC.System.Exec(/usr/bin/firefox)</onclick>
# firefox.sh /usr/bin/xinit /usr/bin/firefox -- :0 -nolisten tcp

pacaur -S xbmc-addon-steam-launcher
#pacaur -S retroarch-phoenix-git

# add xbmc-addon-steam-launcher to menu?

#<item id="12">
#<label>Firefox</label>
#<onclick>XBMC.System.Exec(/usr/bin/firefox)</onclick>
#<icon>special://skin/backgrounds/firefox.jpg</icon>
#</item>

# /usr/bin/steam -bigpicture
# /usr/bin/xinit /usr/bin/steam "-bigpicture" -- :1 -nolisten tcp



