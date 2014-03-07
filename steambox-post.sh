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
		sudo pacman -Sy libnewt
	fi
}

enable_ssh(){
	sudo pacman -S --needed openssh
	sudo systemctl enable sshd.service
	sudo systemctl start sshd.service
}

install_aur_helper() {
	if ! command -v pacaur ; then
		echo "## Installing pacaur AUR Helper"

		sudo pacman -S --noconfirm --needed wget base-devel

		if ! grep -q "EDITOR" ~/.bashrc ; then 
			echo "export EDITOR=\"nano\"" >> ~/.bashrc
		fi

		curl https://aur.archlinux.org/packages/co/cower/cower.tar.gz | tar -zx
		pushd cower
		makepkg -s PKGBUILD --install `if [ $(id -u) = 0 ]; then echo "--asroot" ; fi`
		popd
		rm -rf cower

		curl https://aur.archlinux.org/packages/pa/pacaur/pacaur.tar.gz | tar -zx
		pushd pacaur
		makepkg -s PKGBUILD --install `if [ $(id -u) = 0 ]; then echo "--asroot" ; fi`
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

			echo -e 'Server = http://catalyst.wirephire.com/repo/catalyst/$arch\nServer = http://70.239.162.206/catalyst-mirror/repo/catalyst/$arch\nServer = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/$arch' | sudo tee /etc/pacman.d/catalyst

			sudo pacman-key --keyserver pgp.mit.edu --recv-keys 0xabed422d653c3094
			sudo pacman-key --lsign-key 0xabed422d653c3094

			if ! grep -q "\[catalyst\]" /etc/pacman.conf ; then
				echo -e "\n[catalyst]\nInclude = /etc/pacman.d/catalyst" | sudo tee --append /etc/pacman.conf
			fi
			 
			sudo pacman -Syy

			sudo pacman -S --needed base-devel linux-headers mesa-demos qt4 acpid
			 
			sudo pacman -S catalyst-hook catalyst-utils

			if [[ `uname -m` == x86_64 ]]; then
				sudo pacman -S lib32-catalyst-utils
			fi
			 
			sudo sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$# nomodeset\"#" /etc/default/grub
			 
			echo "blacklist radeon" | sudo tee /etc/modprobe.d/blacklist-radeon.conf
			echo -e "blacklist snd_hda_intel\nblacklist snd_hda_codec_hdmi" | sudo tee /etc/modprobe.d/blacklist-hdmi.conf

			sudo grub-mkconfig -o /boot/grub/grub.cfg

			sudo systemctl enable atieventsd
			sudo systemctl start atieventsd

			sudo systemctl enable temp-links-catalyst
			sudo systemctl start temp-links-catalyst
			
			sudo systemctl enable catalyst-hook
			sudo systemctl start catalyst-hook

			sudo aticonfig --initial
		;;
	    	5)
			echo "## installing AMD open-source"
			sudo pacman -S xf86-video-ati
			# radeon.dpm=1 radeon.audio=1
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

	if whiptail --yesno "Install ttf-ms-fonts?" 8 40 ; then pacaur -S ttf-ms-fonts ; fi
}

improve_readability() {
	pacaur -S cope-git
}

install_grub_holdshift() {
	echo "## Installing grub-holdshift"

	pacaur -S grub-holdshift
	 
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
	sudo passwd -l root
}

install_enhanceio() {
	sudo pacman -S --needed dkms
	sudo systemctl enable dkms.service
	pacaur -S enhanceio-dkms-git
}

install_steam() {
	sudo pacman -S steam
	pacaur -S --asroot steam-standalone
	#sudo pacman -S accountsservice
}

install_native_steamruntime() {
	sudo pacman -S pkgfile
	sudo pkgfile --update
	#sudo su steam -c "file /var/lib/steam/.steam/steam/ubuntu12_32/*\.so*"|cut -d ":" -f1|xargs sudo ldd|cut -d " " -f1 |sort|uniq|xargs -n1 pkgfile --repo multilib | cut -d '/' -f2 | xargs sudo pacman -S
	sudo su steam -c "file /var/lib/steam/.steam/steam/ubuntu12_32/*\.so*"|cut -d ":" -t|uniq|xargs -n1 pkgfile --repo multilib | cut -d '/' -f2|uniq|grep -v nvidia|grep -v gcc-libs-multilib|xargs sudo pacman --noconfirm -S
}

fix_machine_id() {
	rm /var/lib/dbus/machine-id
	ln -s /etc/machine-id /var/lib/dbus/machine-id
}

install_xbmc() {
	sudo pacman -S xbmc 
	# lirc
	sudo systemctl enable xbmc
	pacaur -S --asroot xbmc-addon-steam-launcher

	# firefox.sh /usr/bin/xinit /usr/bin/firefox -- :0 -nolisten tcp

	#<item id="12">
	#<label>Firefox</label>
	#<onclick>XBMC.System.Exec(/usr/bin/firefox)</onclick>
	#<icon>special://skin/backgrounds/firefox.jpg</icon>
	#</item>
}

install_xboxdrv() {
	pacaur -S --asroot xboxdrv
	echo "blacklist xpad" | sudo tee /etc/modprobe.d/xpad_blacklist.conf
	sudo rmmod xpad
	sudo sed -i -e '/ExecStart/s/$/ --daemon/' /usr/lib/systemd/system/xboxdrv.service
	echo -e "\nnext-controller = true\nnext-controller = true\nnext-controller = true" | sudo tee --append /etc/conf.d/xboxdrv
	#  [xboxdrv-daemon]\ndbus = disabled
	sudo systemctl enable xboxdrv.service
}

fix_audio() {
	# sudo pacman -S alsa-utils
	#aplay -l | whiptail
	# echo "load-module module-alsa-sink device=hw:0,7" | sudo tee --apend /etc/pulse/default.pa
	echo -e 'defaults.pcm.!card 0\ndefaults.pcm.!device 7' | sudo tee /var/lib/steam/.asoundrc
	sudo chown steam:steam /var/lib/steam/.asoundrc
}

fix_joystick_perms() {
	#sudo pacman -S xf86-input-joystick joyutils
	#pacman -S lib32-sdl sdl2
	#find /dev/input/by-path/ -name '*event-joystick' | xargs sudo chmod +r
	echo 'KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", MODE:="0644"' | sudo tee /etc/udev/rules.d/joystick-perm.rules
}

fix_networkmanager_perms() {
	cat <<-'EOF' | sudo tee /etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 && subject.isInGroup("network")) {
    return polkit.Result.YES;
  }
});
EOF
}

check_whiptail

enable_ssh

install_aur_helper
install_multilib_repo
install_xorg
install_video_drivers
install_pulse_audio

install_grub_holdshift
install_fonts

fix_joystick_perms

sudo pacman -S unrar upower udisks xterm

install_steam

if whiptail --defaultno --yesno "install and boot to xbmc? (else will boot into steam)" 8 40 ; then
	install_xbmc
else
	sudo systemctl enable steam-standalone.service
fi

sudo systemctl enable NetworkManager-wait-online.service

sudo pacman -S flashplugin
if [[ `uname -m` == x86_64 ]]; then
	sudo pacman -S lib32-flashplugin
fi

#if whiptail --yesno "disable root account?" 8 40 ; then
#	disable_root_login
#fi

#pacaur -S --asroot retroarch-phoenix-git
#pacaur -S --asroot xorg-launch-helper


# todo:
# keyboard ? xf86-input-evdev ?

# reboot/shutdown permissions for steam?
# dbus-send --system --print-reply --dest=org.freedesktop.ConsoleKit /org/freedesktop/ConsoleKit/Manager org.freedesktop.ConsoleKit.Manager.Stop
# dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Reboot boolean:true
# dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:true

#PulseAudio connect failed (used only for Mic Volume Control) with error: Access denied

