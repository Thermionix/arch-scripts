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
	if ! command -v pacaur ; then
		echo "## Installing pacaur AUR Helper"

		sudo pacman -Sy --noconfirm --needed wget base-devel

		if ! grep -q "EDITOR" ~/.bashrc ; then 
			echo "export EDITOR=\"nano\"" >> ~/.bashrc
		fi

		#sed -i -e "/^#keyserver-options auto-key-retrieve/s/#//" ~/.gnupg/gpg.conf
		curl https://aur.archlinux.org/cgit/aur.git/snapshot/cower.tar.gz | tar -zx
		pushd cower
		makepkg -s PKGBUILD --install --noconfirm --ignorearch --skippgpcheck
		popd
		rm -rf cower

		curl https://aur.archlinux.org/cgit/aur.git/snapshot/pacaur.tar.gz | tar -zx
		pushd pacaur
		makepkg -s PKGBUILD --install --noconfirm
		popd
		rm -rf pacaur
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
	sudo pacman -Sy --noconfirm xorg-server xorg-server-utils xorg-xinit mesa libtxc_dxtn
	if [[ `uname -m` == x86_64 ]]; then
		sudo pacman -S --noconfirm lib32-libtxc_dxtn
	fi
}

install_video_drivers() {
	case $(whiptail --menu "Choose a video driver" 20 60 12 \
	"1" "vesa (generic)" \
	"2" "virtualbox" \
	"3" "Intel" \
	"4" "AMD proprietary (catalyst)" \
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
			sudo pacman -S --noconfirm xf86-video-intel

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-intel-dri
			fi
		;;
		4)
			echo "## installing AMD proprietary (catalyst)"

cat <<-'EOF' | sudo tee /etc/pacman.d/catalyst
Server = http://catalyst.wirephire.com/repo/catalyst/$arch
Server = http://70.239.162.206/catalyst-mirror/repo/catalyst/$arch
Server = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/$arch
Server = http://mirror.hactar.bz/Vi0L0/catalyst/$arch
EOF

			sudo pacman-key --keyserver pgp.mit.edu --recv-keys 0xabed422d653c3094
			sudo pacman-key --lsign-key 0xabed422d653c3094

			if ! grep -q "\[catalyst\]" /etc/pacman.conf ; then
				echo -e "\n[catalyst]\nInclude = /etc/pacman.d/catalyst" | sudo tee --append /etc/pacman.conf
			fi
			 
			sudo pacman -Syy

			sudo pacman -S --noconfirm catalyst-hook catalyst-utils catalyst-libgl acpid

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S --noconfirm lib32-catalyst-utils lib32-catalyst-libgl
			fi
			 
			sudo sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$# nomodeset\"#" /etc/default/grub
			sudo grub-mkconfig -o /boot/grub/grub.cfg
			 
			echo "blacklist radeon" | sudo tee /etc/modprobe.d/blacklist-radeon.conf
			echo -e "blacklist snd_hda_intel\nblacklist snd_hda_codec_hdmi" | sudo tee /etc/modprobe.d/blacklist-hdmi.conf

			sudo systemctl enable atieventsd
			sudo systemctl start atieventsd

			sudo systemctl enable temp-links-catalyst
			sudo systemctl start temp-links-catalyst
			
			sudo systemctl enable catalyst-hook
			sudo systemctl start catalyst-hook

			sudo aticonfig --initial
			# aticonfig --initial=dual-head --screen-layout=left
			# aticonfig --set-pcs-u32=DDX,EnableTearFreeDesktop,1
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
	sudo pacman -S --noconfirm network-manager-applet mate-disk-utility gnome-icon-theme

	echo "fixing mate-menu icon for gnome icon theme"
	mkdir -p ~/.icons/gnome/24x24/places
	wget -O ~/.icons/gnome/24x24/places/start-here.png http://i.imgur.com/vBpJDs7.png

	pacaur -S --noedit --noconfirm adwaita-x-dark-and-light-theme
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

