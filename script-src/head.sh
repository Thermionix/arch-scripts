#!/bin/bash

set -e

check_notroot() {
	if [ $(id -u) = 0 ]; then
		echo "Don't run as root!"
		exit 1
	fi
}

check_whiptail() {
	`command -v whiptail >/dev/null 2>&1 || { echo "whiptail (pkg libnewt) required for this script" >&2 ; sudo pacman -Sy libnewt ; }`
}

enable_ssh(){
	sudo pacman -S --needed openssh
	sudo systemctl enable sshd.service
	sudo systemctl start sshd.service
}

install_aur_helper() {
	if ! command -v whiptail ; then
		echo "## Installing AUR Helper"

		sudo pacman -S --noconfirm --needed wget base-devel

		if ! grep -q "EDITOR" ~/.bashrc ; then 
			echo "export EDITOR=\"nano\"" >> ~/.bashrc
		fi

		curl https://aur.archlinux.org/packages/co/cower/cower.tar.gz | tar -zx
		pushd cower
		makepkg -s PKGBUILD --install --asroot
		popd
		rm -rf cower

		curl https://aur.archlinux.org/packages/pa/pacaur/pacaur.tar.gz | tar -zx
		pushd pacaur
		makepkg -s PKGBUILD --install --asroot
		popd
		rm -rf pacaur
	fi
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
	sudo pacman -S xorg-server xorg-server-utils xorg-xinit mesa
	sudo pacman -S libtxc_dxtn
	if [[ `uname -m` == x86_64 ]]; then
		sudo pacman -S lib32-libtxc_dxtn
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

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S lib32-intel-dri
			fi
		;;
		4)
			echo "## installing AMD proprietary (catalyst)"

			if ! grep -q "\[catalyst\]" /etc/pacman.conf ; then
				echo -e "\n[catalyst]\nInclude = /etc/pacman.d/catalyst" | sudo tee --append /etc/pacman.conf
			fi
			 
			`echo -e "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch\nServer = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch\nServer = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | sudo tee /etc/pacman.d/catalyst`
			 
			sudo pacman-key --keyserver pgp.mit.edu --recv-keys 0xabed422d653c3094
			sudo pacman-key --lsign-key 0xabed422d653c3094
			 
			sudo pacman -Syy
			 
			sudo pacman -S --needed base-devel linux-headers mesa-demos qt4
			 
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
	    	5)
			echo "## installing AMD open-source"
			sudo pacman -S xf86-video-ati
		;;
		6)
			echo "## installing NVIDIA open-source (nouveau)"
			sudo pacman -S xf86-video-nouveau
			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S lib32-nouveau-dri
			fi
		;;
		7)
			echo "## installing NVIDIA proprietary"
			sudo pacman -S nvidia
			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S lib32-nvidia-libgl
			fi
		;;
	esac
}

install_fonts() {
	echo "## Installing Fonts"
	sudo pacman -S ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
	if ! test -f /etc/fonts/conf.d/70-no-bitmaps.conf ; then sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/ ; fi

	if whiptail --yesno "Install ttf-ms-fonts?" 8 40 ; then pacaur -S --asroot ttf-ms-fonts ; fi
}

improve_readability() {
	pacaur -S --asroot cope-git
}

install_grub_holdshift() {
	echo "## Installing grub-holdshift"

	pacaur -S --asroot grub-holdshift
	 
	if ! grep -q "GRUB_FORCE_HIDDEN_MENU" /etc/default/grub ; then
		echo -e "\nGRUB_FORCE_HIDDEN_MENU=\"true\"" | sudo tee --append /etc/default/grub
	fi
	sudo sed -i -e '/GRUB_TIMEOUT/s/5/0/' /etc/default/grub
	 
	sudo grub-mkconfig -o /boot/grub/grub.cfg
}

install_pulse_audio() {
	echo "## Installing PulseAudio"
	sudo pacman -S pulseaudio pulseaudio-alsa
	if [[ `uname -m` == x86_64 ]]; then
		sudo pacman -S lib32-libpulse lib32-alsa-plugins
	fi
}

disable_root_login() {
	passwd -l root
}

install_enhanceio() {
	pacaur -S --asroot enhanceio-dkms-git

}
