#!/bin/bash

echo "###### Do not run as root"
command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }

install_aur_helper() {
	echo "## Installing AUR Helper"
	sudo pacman -S --needed wget base-devel
	if ! grep -q "EDITOR" ~/.bashrc ; then 
		echo "export EDITOR=\"nano\"" >> ~/.bashrc
	fi
	 
	mkdir packerbuild
	pushd packerbuild
	 
	wget http://aur.archlinux.org/packages/pa/packer/packer.tar.gz
	wget http://aur.archlinux.org/packages/pa/packer/PKGBUILD
	 
	makepkg -s PKGBUILD --install
	 
	popd
	rm -rf packerbuild
}

install_multilib_repo() {
	if [[ `uname -m` == x86_64 ]]; then
		echo "## x86_64 detected, adding multilib repository"
		if ! grep -q "\[multilib\]" /etc/pacman.conf ; then
			echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
		else
			sudo sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
		fi
	fi
	sudo pacman -Syy
}

install_xorg() {
	echo "## Installing Xorg"
	sudo pacman -S xorg-server xorg-server-utils xorg-xinit mesa
}

install_video_drivers() {
	echo "## Installing Video Drivers"

	driverlist=("vesa" "virtualbox" "intel" "catalyst")
	select OPT in "${driverlist[@]}"; do
	case "$REPLY" in
    	1)
			echo "## installing vesa"
			sudo pacman -S xf86-video-vesa
		;;
    	2)
			echo "## installing virtualbox"
			sudo pacman -S virtualbox-guest-utils
		;;
    	3)
			echo "## installing intel"
			sudo pacman -S xf86-video-intel
		;;
    	4)
			echo "## installing catalyst"

			if ! grep -q "\[catalyst\]" /etc/pacman.conf ; then
				echo -e '\n[catalyst]\nInclude = /etc/pacman.d/catalyst' | sudo tee --append /etc/pacman.conf
			fi
			 
			echo -e "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch\nServer = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch\nServer = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | sudo tee /etc/pacman.d/catalyst
			 
			sudo pacman-key --keyserver pgp.mit.edu --recv-keys 0xabed422d653c3094
			sudo pacman-key --lsign-key 0xabed422d653c3094
			 
			sudo pacman -Syy
			 
			sudo pacman -S --needed base-devel linux-headers mesa-demos qt4
			sudo pacman -S libtxc_dxtn lib32-libtxc_dxtn
			 
			sudo pacman -S catalyst-hook catalyst-utils

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S lib32-catalyst-utils
			fi
			 
			sudo sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$# nomodeset\"#" /etc/default/grub
			 
			echo "blacklist radeon" | sudo tee /etc/modprobe.d/blacklist-radeon.conf
			echo -e "blacklist snd_hda_intel\nblacklist snd_hda_codec_hdmi" | sudo tee /etc/modprobe.d/blacklist-hdmi.conf

			sudo grub-mkconfig -o /boot/grub/grub.cfg
			 
			sudo systemctl enable catalyst-hook
			sudo systemctl start catalyst-hook
			 
			# sudo reboot
			# sudo aticonfig --initial
			# sudo aticonfig --initial=dual-head --screen-layout=right
			# sudo aticonfig --tls=off
		;;
		*)
	        invalid_option
        ;;
	esac
	[[ -n $OPT ]] && break
	done
}

install_desktop_environment() {
	echo "## Installing Desktop Environment"

	#if case = mate
	#pacman -S mate mate-extras
	#echo "exec mate-session" > ~/.xinitrc

	#if case = gnome
	sudo pacman -S --ignore empathy --ignore epiphany --ignore totem gnome gnome-flashback-session gnome-applets
	sudo pacman -S gedit gnome-tweak-tool nautilus-open-terminal file-roller dconf-editor
	echo "exec gnome-session --session=gnome-flashback" > ~/.xinitrc
}

install_network_manager() {
	echo "## Installing NetworkManager"
	sudo pacman -S networkmanager network-manager-applet networkmanager-dispatcher-ntpd
	sudo systemctl disable dhcpcd
	sudo systemctl stop dhcpcd
	sudo systemctl enable NetworkManager
	sudo systemctl start NetworkManager
}

install_fonts() {
	echo "## Installing Fonts"
	sudo pacman -S ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
	sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
	read -p "Install ttf-ms-fonts? [y/N]: " OPTION
		[[ $OPTION == y ]] && packer -S ttf-ms-fonts
}

install_scanning() {
	sudo pacman -S sane xsane
	sudo usermod -a -G scanner `whoami`
}

install_desktop_applications() {
	echo "## Installing Desktop Applications"

	if ! grep -q "complete -cf sudo" ~/.bashrc ; then 
		echo "complete -cf sudo" >> ~/.bashrc
	fi
	
	if ! grep -q "bash_aliases" ~/.bashrc ; then 
		echo -e "if [ -f ~/.bash_aliases ]; then\n. ~/.bash_aliases\nfi" >> ~/.bashrc
	fi
	
	if ! grep -q "yolo" ~/.bash_aliases ; then 
		echo "alias yolo='packer -Syu'" >> ~/.bash_aliases
	fi
	
	sudo pacman -S firefox vlc clementine gstreamer0.10-plugins flashplugin
	 
	sudo pacman -S openssh ntfsprogs rsync p7zip unrar zip gparted
	 
	sudo pacman -S mumble gimp

	read -p "Install Gaming? [y/N]: " OPTION
		[[ $OPTION == y ]] && install_gaming_applications
}

install_gaming_applications() {
	sudo pacman -S steam
	packer -S sdl-nokeyboardgrab
	#echo "options usbhid mousepoll=2" | sudo tee /etc/modprobe.d/mousepolling.conf
}

install_wine() {
	echo "## Installing Wine"

	sudo pacman -S wine winetricks wine-mono wine_gecko
	sudo pacman -S alsa-lib alsa-plugins lib32-alsa-lib lib32-alsa-plugins lib32-mpg123 libpulse mpg123 lib32-libpulse lib32-openal
	 
	#winetricks videomemorysize=2048 3072?
	WINEARCH=win32 winecfg

	echo "export WINEDLLOVERRIDES='winemenubuilder.exe=d'" >> ~/.bashrc
	sed -i -e "/^text/d" -e "/^image/d" ~/.local/share/applications/mimeinfo.cache
	rm ~/.local/share/applications/wine-extension*
}

install_grub_holdshift() {
	echo "## Installing grub-holdshift"

	packer -S grub-holdshift
	 
	if ! grep -q "GRUB_FORCE_HIDDEN_MENU" /etc/default/grub ; then
		echo -e "\nGRUB_FORCE_HIDDEN_MENU=\"true\"" | sudo tee --append /etc/default/grub
	fi
	 
	sudo grub-mkconfig -o /boot/grub/grub.cfg
}

install_x_autostart() {
	echo "## Installing X Autostart"
	if ! grep -q "exec startx" ~/.bash_profile ; then 
		test -f /home/$username/.bash_profile || cp /etc/skel/.bash_profile ~/.bash_profile
		echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> ~/.bash_profile
	fi
}

install_pulse_audio() {
	echo "## Installing PulseAudio"
	sudo pacman -S pulseaudio pulseaudio-alsa pavucontrol
}

install_printing() {
	echo "## Installing Printing"
	sudo pacman -S cups cups-filters foomatic-filters ghostscript gsfonts system-config-printer
	sudo systemctl enable cups
	sudo systemctl start cups
}

install_gsettings() {
	echo "## Toggle some settings in gnome environment"
	echo "# Only works after running startx!"
	gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
	gsettings set org.gnome.nautilus.preferences sort-directories-first 'true'
	gsettings set org.gtk.Settings.FileChooser show-hidden 'true'
	gsettings set org.gnome.desktop.background show-desktop-icons 'true'

	if gsettings list-schemas | grep -q gedit ; then
		echo "# updating gedit settings"
		gsettings set org.gnome.gedit.preferences.editor create-backup-copy 'false'
		gsettings set org.gnome.gedit.preferences.editor wrap-mode 'none'
		gsettings set org.gnome.gedit.preferences.editor display-line-numbers 'true'
		gsettings set org.gnome.gedit.preferences.editor bracket-matching 'true'
	fi

	mkdir -p ~/.config/gtk-3.0
	if [ ! -f ~/.config/gtk-3.0/settings.ini ] ; then
		echo -e "[Settings]\ngtk-recent-files-max-age=0\ngtk-recent-files-limit=0" > ~/.config/gtk-3.0/settings.ini
	fi
	rm ~/.local/share/recently-used.xbel

	#gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \"['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']\"
	#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name \"terminal\"
	#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command \"gnome-terminal\"
	#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding \"\<Ctrl\>\<Alt\>t\"
}


list_aur_pkgs() {
	echo "## Listing packages from AUR"
	sudo pacman -Qm | awk '{print $1}' | less
}

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
16 "List AUR PKGs" off
17 "reboot" off
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
			list_aur_pkgs
		;;
		17)
			reboot
		;;
    esac
done

