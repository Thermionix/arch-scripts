
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
	echo -e "defaults.pcm.!card 1\ndefaults.pcm.!device 7" | sudo tee /var/lib/steam/.asoundrc
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

if [[ `uname -m` == x86_64 ]]; then
	sudo pacman -S lib32-flashplugin
fi

#if whiptail --yesno "disable root account?" 8 40 ; then
#	disable_root_login
#fi

#if whiptail --yesno "add xboxdrv (for xbox gamepads)?" 8 40 ; then
#	install_xboxdrv
#fi

#pacaur -S --asroot retroarch-phoenix-git
#pacaur -S --asroot xorg-launch-helper


# todo:
# reboot/shutdown permissions for steam?
# keyboard ? xf86-input-evdev ?

#PulseAudio connect failed (used only for Mic Volume Control) with error: Access denied

