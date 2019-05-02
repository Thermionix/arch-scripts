#!/bin/bash

set -e

check_notroot() {
	if [ $(id -u) = 0 ]; then
		echo "Don't run as root!"
		exit 1
	fi
}

check_whiptail() {
	if ! command -v whiptail ; then
		echo "whiptail (pkg libnewt) required for this script"
		sudo pacman -Sy --noconfirm libnewt
	fi
}

enable_ssh(){
	sudo pacman -Sy --noconfirm --needed openssh
	sudo systemctl enable sshd.service
	sudo systemctl start sshd.service
}

install_aur_helper() {
	if ! command -v yay ; then
		echo "## Installing yay AUR Helper"

		sudo pacman -Sy --noconfirm --needed wget base-devel

		if ! grep -q "EDITOR" ~/.bashrc ; then 
			echo "export EDITOR=\"nano\"" >> ~/.bashrc
		fi

		gpg --list-keys
		if [ ! -f ~/.gnupg/gpg.conf ] ; then
			echo "keyserver-options auto-key-retrieve" > ~/.gnupg/gpg.conf
		else
			sed -i -e "/^#keyserver-options auto-key-retrieve/s/#//" ~/.gnupg/gpg.conf
		fi
		
		curl https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz | tar -zx
		pushd yay
		makepkg -s PKGBUILD --install --noconfirm
		popd
		rm -rf yay
	fi

	echo "Defaults passwd_timeout=0" | sudo tee /etc/sudoers.d/timeout
	echo 'Defaults editor=/usr/bin/nano, !env_editor' | sudo tee /etc/sudoers.d/nano
}

install_multilib_repo() {
	if [[ `uname -m` == x86_64 ]]; then
		echo "## x86_64 detected, adding multilib repository"
		if ! grep -q "\[multilib\]" /etc/pacman.conf ; then
			echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
		else
			sudo sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
		fi
		sudo pacman -Syy
	fi
}

install_xorg() {
	echo "## Installing Xorg"
	sudo pacman -Sy --noconfirm xorg-server xorg-xinit
}

install_video_drivers() {
	case $(whiptail --menu "Choose a video driver" 20 60 12 \
	"1" "vesa (generic)" \
	"2" "virtualbox" \
	"3" "Intel" \
	"5" "AMD open-source" \
	"6" "NVIDIA open-source (nouveau)" \
	"7" "NVIDIA proprietary" \
	"8" "Raspberry Pi (fbdev)" \
	3>&1 1>&2 2>&3) in
		1)
			echo "## installing vesa"
			sudo pacman -S --noconfirm xf86-video-vesa
		;;
		2)
			echo "## installing virtualbox"
			sudo pacman -S --noconfirm virtualbox-guest-utils
		;;
		3)
			echo "## installing intel"
			sudo pacman -S --noconfirm xf86-video-intel vulkan-intel

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-intel-dri
			fi
		;;
	    	5)
			echo "## installing AMD open-source"
			sudo pacman -S --noconfirm xf86-video-ati
			# radeon.dpm=1 radeon.audio=1

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-ati-dri
			fi
		;;
		6)
			echo "## installing NVIDIA open-source (nouveau)"
			sudo pacman -S --noconfirm xf86-video-nouveau
			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-nouveau-dri
			fi
		;;
		7)
			echo "## installing NVIDIA proprietary"
			sudo pacman -S --noconfirm nvidia
			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-nvidia-libgl
			fi
		;;
		8)
			echo "## installing driver for Raspberry Pi (fbdev)"
			sudo pacman -S --noconfirm xf86-video-fbdev
		;;
	esac
}

install_fonts() {
	echo "## Installing Fonts"
	sudo pacman -S --noconfirm ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
	if ! test -f /etc/fonts/conf.d/70-no-bitmaps.conf ; then sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/ ; fi
}

disable_root_login() {
	sudo passwd -l root
}

enable_autologin() {
	username=`whoami`
	if whiptail --yesno "enable autologin for user: $username?" 8 40 ; then
		echo "## enabling autologin for user: $username"
		sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
		echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" \
			| sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf
	fi
}

install_x_autostart() {
	echo "## Installing X Autostart"
	if ! grep -q "exec startx" ~/.bash_profile ; then 
		test -f /home/$username/.bash_profile || cp /etc/skel/.bash_profile ~/.bash_profile
		echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> ~/.bash_profile
	fi
}

paccache_cleanup() {

sudo pacman -S --noconfirm pacman-contrib

cat <<-'EOF' | sudo tee /etc/systemd/system/paccache-clean.timer
[Unit]
Description=Clean pacman cache weekly

[Timer]
OnBootSec=10min
OnCalendar=weekly
Persistent=true     
 
[Install]
WantedBy=timers.target
EOF

cat <<-'EOF' | sudo tee /etc/systemd/system/paccache-clean.service
[Unit]
Description=Clean pacman cache

[Service]
Type=oneshot
ExecStart=/usr/bin/paccache -rk2
ExecStart=/usr/bin/paccache -ruk0
EOF

sudo systemctl enable paccache-clean.timer

}

pacman_utils() {
	# install haveged for better randomness
	sudo pacman -S haveged
	sudo systemctl enable haveged
	sudo systemctl start haveged
	# 

}

install_desktop_environment() {
	sudo pacman -S --noconfirm mate mate-extra pulseaudio

	echo "exec mate-session" > ~/.xinitrc
	sudo pacman -S --noconfirm network-manager-applet gnome-icon-theme

	echo "Settings lock-screen background image to solid black"
cat <<-'EOF' | sudo tee /usr/share/glib-2.0/schemas/mate-background.gschema.override
[org.mate.background]
color-shading-type='solid'
picture-options='scaled'
picture-filename=''
primary-color='#000000'
EOF
	sudo glib-compile-schemas /usr/share/glib-2.0/schemas/

	echo "fixing mate-menu icon for gnome icon theme"

	sudo wget -O /usr/share/pixmaps/arch-menu.png http://i.imgur.com/vBpJDs7.png
	gsettings set org.mate.panel.menubar icon-name arch-menu

	yay -S --noconfirm adwaita-x-dark-and-light-theme
}

check_notroot
check_whiptail

cmd=(whiptail --separate-output --checklist "Select options:" 22 60 16)
options=(
1 "AUR Helper" off
2 "Enable multilib repository" off
3 "Xorg" off
4 "Video Driver Selection" off
5 "MATE Desktop Environment" off
6 "Fonts" off
7 "Enable X autostart" off
8 "Enable autologin" off
9 "paccache-clean (weekly service)" off
10 "reboot" off
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
			install_fonts
		;;
		7)
			install_x_autostart
		;;
		8)
			enable_autologin
		;;
		9)
			paccache_cleanup
		;;
		10)
			sudo reboot
		;;
    esac
done

