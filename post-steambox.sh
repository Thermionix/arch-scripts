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
install_steam
install_grub_holdshift

sudo pacman -S wmctrl

#disable_root_login

# add xbmc menu item?
# <onclick>XBMC.System.Exec(/usr/bin/firefox)</onclick>

pacaur -S xbmc-addon-steam-launcher
# add xbmc-addon-steam-launcher to menu?

if sudo [ ! -f /etc/polkit-1/rules.d/10-xbmc.rules ] ; then
cat << EOF | sudo tee /etc/polkit-1/rules.d/10-xbmc.rules
polkit.addRule(function(action, subject) {
	if(action.id.match("org.freedesktop.login1.") && subject.isInGroup("power")) {
	    return polkit.Result.YES;
	}
});

polkit.addRule(function(action, subject) {
	if (action.id.indexOf("org.freedesktop.udisks") == 0 && subject.isInGroup("storage")) {
	    return polkit.Result.YES;
	}
});
EOF
fi

