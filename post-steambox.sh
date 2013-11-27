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

#disable_root_login
