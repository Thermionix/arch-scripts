#!/bin/bash

if [[ -f `pwd`/post-shared.sh ]]; then
	source post-shared.sh
else
	echo "missing file: shared-functions.sh"
	exit 1
fi

check_notroot
check_whiptail

cmd=(whiptail --separate-output --checklist "Select options:" 22 60 16)
options=(
1 "AUR Helper" off
2 "enable multilib repository" off
3 "Xorg" off
4 "Video Drivers" off
5 "Desktop Environment" off
6 "Network Manager" off
7 "Fonts" off
8 "Desktop Applications" off
9 "Wine" off
10 "grub-holdshift" off
11 "Printing" off
12 "Scanning" off
13 "Pulseaudio" off
14 "Enable X autostart" off
15 "Gsettings" off
16 "Steam and gaming tweaks" off
17 "Laptop mode" off
18 "List AUR PKGs" off
19 "reboot" off
)
choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

for choice in $choices
do
    case $choice in
		1)
			install_aur_helper
		;;
		2)
			install_multilib_repo
		;;
		3)
			install_xorg
		;;
		4)
			install_video_drivers
		;;
		5)
			install_desktop_environment
		;;
		6)
			install_network_manager
		;;
		7)
			install_fonts
		;;
		8)
			install_desktop_applications
		;;
		9)
			install_wine
		;;
		10)
			install_grub_holdshift
		;;
		11)
			install_printing
		;;
		12)
			install_scanning
		;;
		13)
			install_pulse_audio
		;;
		14)
			install_x_autostart
		;;
		15)
			install_gsettings
		;;
		16)
			install_steam
		;;
		17)
			install_laptop_mode
		;;
		18)
			list_aur_pkgs
		;;
		19)
			sudo reboot
		;;
    esac
done

