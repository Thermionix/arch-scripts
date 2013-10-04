#!/bin/bash

`command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }`

if [ $(id -u) = 0 ]; then
	echo "Don't run as root!"
	exit 1
fi

install_aur_helper() {
	echo "## Installing AUR Helper"

	sudo pacman -S --needed wget base-devel

	if ! grep -q "EDITOR" ~/.bashrc ; then 
		echo "export EDITOR=\"nano\"" >> ~/.bashrc
	fi

	# whiptail choose pacaur pacaur yaourt?
	# define in variable?

	# INSTALL COWER
	 
	mkdir -p pacaurbuild
	pushd pacaurbuild
	 
	wget http://aur.archlinux.org/packages/pa/pacaur/pacaur.tar.gz
	wget http://aur.archlinux.org/packages/pa/pacaur/PKGBUILD
	 
	makepkg -s PKGBUILD --install
	 
	popd
	rm -rf pacaurbuild
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
	case $(whiptail --menu "Choose a video driver" 20 60 12 \
	"1" "vesa (generic)" \
	"2" "virtualbox" \
	"3" "intel" \
	"4" "catalyst" \
	3>&1 1>&2 2>&3) in
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
				echo -e "\n[catalyst]\nInclude = /etc/pacman.d/catalyst" | sudo tee --append /etc/pacman.conf
			fi
			 
			`echo -e "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch\nServer = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch\nServer = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | sudo tee /etc/pacman.d/catalyst`
			 
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
	esac	
}

install_desktop_environment() {
	case $(whiptail --menu "Choose a Desktop Environment" 20 60 12 \
	"1" "gnome" \
	"2" "mate" \
	3>&1 1>&2 2>&3) in
		1)
			sudo pacman -S --ignore empathy --ignore epiphany --ignore totem gnome gnome-flashback-session gnome-applets
			sudo pacman -S gedit gnome-tweak-tool nautilus-open-terminal file-roller dconf-editor
			echo "exec gnome-session --session=gnome-flashback" > ~/.xinitrc
			pacaur -S mediterraneannight-theme
		;;
		2)
			pacman -S mate mate-extras
			echo "exec mate-session" > ~/.xinitrc
		;;
	esac
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
	whiptail --yesno "Install ttf-ms-fonts?" 8 40 && { pacaur -S ttf-ms-fonts ; }
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
		echo "alias yolo='pacaur -Syu'" >> ~/.bash_aliases
	fi

	# whiptail checklist following	
	sudo pacman -S firefox vlc gstreamer0.10-plugins flashplugin

	sudo pacman -S quodlibet # clementine guayadeque
	 
	sudo pacman -S openssh ntfsprogs rsync p7zip unrar zip gparted
	 
	sudo pacman -S mumble gimp mtpfs minitube midori bleachbit gvfs-smb
}

install_laptop_mode() {
	# tpfanco
	sudo pacaur -S laptop-mode-tools
	sudo systemctl enable laptop-mode.service

	# cpupower frequency-info

	# https://wiki.archlinux.org/index.php/TLP

	#packer -S tpfand
	#sudo systemctl start tpfand
	#sudo systemctl enable tpfand

	# append to /etc/default/grub ^GRUB_CMDLINE_LINUX_DEFAULT "i915_enable_rc6=1 i915_enable_fbc=1"
}

install_pacman_gui() {
	sudo pacman -S gnome-packagekit

	#%wheel ALL = NOPASSWD: /usr/bin/pacman -Sy
	#pacaur -S pacman-notifier
	#pacman-notifier &
	#pacman -S pacupdate
	#pacupdate &
}

install_steam_and_tweaks() {
	sudo pacman -S steam
	pacaur -S sdl-nokeyboardgrab
	#echo "options usbhid mousepoll=2" | sudo tee /etc/modprobe.d/mousepolling.conf
}

install_wine() {
	echo "## Installing Wine"

	sudo pacman -S wine winetricks wine-mono wine_gecko
	sudo pacman -S alsa-lib alsa-plugins lib32-alsa-lib lib32-alsa-plugins lib32-mpg123 libpulse mpg123 lib32-libpulse lib32-openal
	 
	WINEARCH=win32 winecfg

	#winetricks videomemorysize=2048 3072?
	`echo "export WINEDLLOVERRIDES='winemenubuilder.exe=d'" >> ~/.bashrc`
	sed -i -e "/^text/d" -e "/^image/d" ~/.local/share/applications/mimeinfo.cache
	rm ~/.local/share/applications/wine-extension*
}

install_grub_holdshift() {
	echo "## Installing grub-holdshift"

	pacaur -S grub-holdshift
	 
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

	if whiptail --yesno "disable gtk list recently-used files?" 8 40 ; then
		mkdir -p ~/.config/gtk-3.0
		if [ ! -f ~/.config/gtk-3.0/settings.ini ] ; then
			`echo -e "[Settings]\ngtk-recent-files-max-age=0\ngtk-recent-files-limit=0" > ~/.config/gtk-3.0/settings.ini`
		fi
		rm ~/.local/share/recently-used.xbel
	fi

	#~/.config/gtk-3.0/settings.ini
	#[Settings]
	#gtk-application-prefer-dark-theme=1


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
			install_steam_and_tweaks
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

