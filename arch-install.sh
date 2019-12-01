#!/bin/bash

set -e
command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }
# TODO : log all output

check_net_connectivity() {
	echo "## checking net connectivity"
	ping -c 2 resolver1.opendns.com

	# TODO : offer wifimenu ?

	# TODO : check default gateway is set?
	#ip route add default via <gw-ip>

	echo "## ensuring the system clock is accurate"
	timedatectl set-ntp true
}

enable_ssh() {
	systemctl start sshd
	ipaddr=`ip addr | grep inet | grep -e enp -e wlan | awk '{print $2}' | cut -d "/" -f1`
	echo "## set passwd for login with ssh root@$ipaddr"
	passwd
	exit
}

set_variables() {
	echo "## defining variables for installation"

	# TODO : offer UTF locale list selection
	# cat /etc/locale.gen | grep "UTF-8" | grep -oP "^#\K[a-zA-Z0-9@._-]+"
	locale=$(whiptail --nocancel --inputbox "Select locale:" 10 40 "en_AU.UTF-8" 3>&1 1>&2 2>&3)

	keyboard=$(whiptail --nocancel --inputbox "Set keyboard:" 10 40 "us" 3>&1 1>&2 2>&3)

	selected_timezone=$(tzselect)

	#new_uuid=$(cat /sys/devices/virtual/dmi/id/product_serial)
	hostname=$(whiptail --nocancel --inputbox "Set hostname:" 10 40 "arch-box" 3>&1 1>&2 2>&3)

	enable_uefi=false
	if [ -d /sys/firmware/efi ] ; then
		if whiptail --yesno "Detected booted in UEFI mode\nInstall for UEFI system?" 8 40 ; then
			enable_uefi=true
		fi
	fi

	# TODO : offer kernel list Stable | Hardened | Longterm | Zen
	enable_lts=false
	if whiptail --defaultno --yesno "Install linux-lts kernel?\n(long-term support stable/server orientated)" 8 60 ; then
		enable_lts=true
	fi

	username=$(whiptail --nocancel --inputbox "Set username for sudo user to be created for this install" 10 40 3>&1 1>&2 2>&3)
	# TODO : confirm and compare password twice
	userpass=$(whiptail --nocancel --passwordbox "Set password for $username" 10 40 3>&1 1>&2 2>&3)

	setup_network=false
	case $(whiptail --nocancel --menu "Choose a network daemon" 20 60 12 \
	"NetworkManager" "(Desktop Orientated)" \
	"systemd-networkd" "(Headless/Server)" \
	"None" "" \
	3>&1 1>&2 2>&3) in
		NetworkManager)
			setup_network="networkmanager"
		;;
		systemd-networkd)
			setup_network="networkd"
		;;
	esac

	enable_ntpd=false
	enable_sshd=false
	if [ $setup_network != false ] ; then
		if whiptail --yesno "Enable network time daemon?\n(synchronize software clock with internet time servers)" 8 60 ; then
			enable_ntpd=true
		fi

		if whiptail --defaultno --yesno "Enable sshd.service?\n(Open Secure Shell daemon)" 8 40 ; then
			enable_sshd=true
		fi
	fi

	enable_swap=false
	if whiptail --defaultno --yesno "enable systemd-swap script?\n(creates hybrid swap space from zram swaps,\n swap files and swap partitions)" 10 60 ; then
		enable_swap=true
	fi

	install_aur=false
	if whiptail --defaultno --yesno "Install AUR helper (yay)?" 8 40 ; then
		install_aur=true
	fi

	#TODO: install desktop / video driver / checklist of software
}

update_locale() {
	echo "## updating locale"
	loadkeys $keyboard
	export LANG=$locale
	sed -i -e "s/#$locale/$locale/" /etc/locale.gen
	locale-gen
}

partition_disk() {
	disks=`parted --list --script | awk -F ": |, |Disk | " '/Disk \// { print $2" "$3$4 }'`
	DSK=$(whiptail --nocancel --menu "Select the Disk to install to" 18 45 10 $disks 3>&1 1>&2 2>&3)

	echo "## WILL COMPLETELY WIPE ${DSK}"
	read -p "Press [Enter] key to continue"
	sgdisk --zap-all ${DSK}

	enable_trim=false
	if [ -n "$(hdparm -I ${DSK} 2>&1 | grep 'TRIM supported')" ]; then
		echo "## detected TRIM support"
		enable_trim=true
	fi

	enable_gpt=false
	if $enable_uefi ; then
		# https://wiki.archlinux.org/index.php/Partitioning
		if whiptail --yesno "use GPT partitioning?" 8 40 ; then
			enable_gpt=true
		fi
	fi

	labelroot="arch-root"
	labelboot="arch-boot"

	if $enable_gpt ; then
		if $enable_uefi ; then
			esp_end=501
			labelesp="arch-esp"
			partesp="/dev/disk/by-partlabel/$labelesp"
		else
			esp_end=2
		fi
	else
		esp_end=1
	fi

	boot_size=$(whiptail --nocancel --inputbox "Set boot partition size:" 10 40 "200" 3>&1 1>&2 2>&3)
	boot_end=$(( ${esp_end} + ${boot_size} ))


	if $enable_gpt ; then
		partroot="/dev/disk/by-partlabel/$labelroot"
		partboot="/dev/disk/by-partlabel/$labelboot"

		parted -s ${DSK} mklabel gpt

		echo "## creating partition bios_grub"
		if $enable_uefi ; then
			parted -s ${DSK} -a optimal unit MB mkpart ESI 1 ${esp_end}
			parted -s ${DSK} set 1 boot on
			parted -s ${DSK} mkfs 1 fat32
			parted -s ${DSK} name 1 $labelesp
		else
			parted -s ${DSK} -a optimal unit MB mkpart primary 1 ${esp_end}
			parted -s ${DSK} set 1 bios_grub on
		fi

		echo "## creating partition $labelboot"
		parted -s ${DSK} -a optimal unit MB mkpart primary ${esp_end} $boot_end
		parted -s ${DSK} name 2 $labelboot

		echo "## creating partition $labelroot"
		parted -s ${DSK} -a optimal unit MB -- mkpart primary $boot_end -1
		parted -s ${DSK} name 3 $labelroot
	else
		parted -s ${DSK} mklabel msdos

		echo "## creating partition $labelboot"
		parted -s ${DSK} -a optimal unit MB mkpart primary ${esp_end} $boot_end
		partboot="${DSK}1"

		echo "## creating partition $labelroot"
		parted -s ${DSK} -a optimal unit MB -- mkpart primary $boot_end -1
		partroot="${DSK}2"
	fi

	whiptail --title "generated partition layout" --msgbox "`parted -s ${DSK} print`" 20 70
}

format_disk() {
	if $enable_uefi ; then
		mkfs.vfat -F 32 $partesp
	fi

	echo "## cleaning $partboot"
	wipefs -a $partboot
	echo "## mkfs $partboot"
	mkfs.ext4 -q $partboot

	mountpoint="/mnt"

	enable_luks=false
	if whiptail --defaultno --yesno "encrypt entire disk with dm-crypt?\n(kernel transparent disk encryption)" 8 40 ; then
		enable_luks=true
	fi

	if $enable_luks ; then
		maproot="croot"

		echo "## encrypting $partroot"
		cryptsetup --batch-mode --force-password --verify-passphrase --cipher aes-xts-plain64 --key-size 512 --hash sha512 luksFormat $partroot
		echo "## opening $partroot"
		cryptsetup luksOpen $partroot $maproot
		echo "## mkfs /dev/mapper/$maproot"
		mkfs.ext4 /dev/mapper/$maproot
		mount /dev/mapper/$maproot $mountpoint
	else
		echo "## mkfs $partroot"
		mkfs.ext4 $partroot
		mount $partroot $mountpoint
	fi

	mkdir -p $mountpoint/boot
	mount $partboot $mountpoint/boot

	if $enable_uefi ; then
		mkdir -p $mountpoint/boot/efi
		mount $partesp $mountpoint/boot/efi
	fi
}

update_mirrorlist() {
	echo "Server=https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
}

install_base(){
	pacman-key --refresh-keys
	echo "## installing base system"
	if ! $enable_lts ; then
		pacstrap $mountpoint base linux linux-firmware
	else
		pacstrap $mountpoint base linux-lts linux-firmware
	fi

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq intel` ; then
		echo "## installing intel ucode"
		pacstrap $mountpoint intel-ucode
	fi

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq amd` ; then
		echo "## installing amd ucode"
		pacstrap $mountpoint amd-ucode
	fi
}

install_multilib_repo() {
	# TODO : FIX THIS
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

configure_fstab(){
	echo "## generating fstab entries"
	genfstab -U -p $mountpoint >> $mountpoint/etc/fstab

	if $enable_trim ; then
		arch_chroot "systemctl enable fstrim.timer"
	fi
}

arch_chroot(){
	arch-chroot $mountpoint /bin/bash -c "${1}"
}

configure_system(){
	echo "## updating locale"
	sed -i -e "s/#$locale/$locale/" $mountpoint/etc/locale.gen
	arch_chroot "locale-gen"
	echo LANG=$locale > $mountpoint/etc/locale.conf
	arch_chroot "export LANG=$locale"

	if $enable_luks ; then
		echo "## adding encrypt hook"
		sed -i -e "/^HOOKS/s/filesystems/encrypt filesystems/" $mountpoint/etc/mkinitcpio.conf
		arch_chroot "mkinitcpio -p linux"
	fi

	echo "## writing vconsole.conf"
	echo "KEYMAP=$keyboard" > $mountpoint/etc/vconsole.conf
	echo "FONT=Lat2-Terminus16" >> $mountpoint/etc/vconsole.conf

	echo "## updating localtime"
	arch_chroot "ln -s /usr/share/zoneinfo/$selected_timezone /etc/localtime"
	arch_chroot "hwclock --systohc --utc"

	echo "## setting hostname"
	echo $hostname > $mountpoint/etc/hostname

	echo "## enabling haveged for better randomness"
	pacstrap $mountpoint haveged
	arch_chroot "systemctl enable haveged"

	echo "## disabling root login"
	arch_chroot "passwd -l root"

	if $enable_swap ; then
		pacstrap $mountpoint systemd-swap
		# TODO : https://github.com/Nefelim4ag/systemd-swap/blob/master/README.md#about-configuration
		sed -i -e "s/swapfc_enabled=0/swapfc_enabled=1/" $mountpoint/etc/systemd/swap.conf
		sed -i -e "s/swapfc_force_preallocated=0/swapfc_force_preallocated=1/" $mountpoint/etc/systemd/swap.conf
		arch_chroot "systemctl enable systemd-swap"
	fi

}

update_mirrorlist_reflector() {
	pacstrap $mountpoint reflector

	shopt -s lastpipe
	arch-chroot $mountpoint	reflector --list-countries | \
	sed 's/[0-9]*//g;s/\(.*\)\([A-Z][A-Z]\)/\2\n\1/g' | \
	readarray countries
	selected_country=$(whiptail --nocancel --menu "select mirrorlist country:" 30 78 22 "${countries[@]}" 3>&1 1>&2 2>&3)

	arch-chroot $mountpoint reflector -c $selected_country -l 5 --sort rate --save /etc/pacman.d/mirrorlist
	# TODO : if server count==0 for mirrorlist set to United States

	mkdir -p $mountpoint/etc/pacman.d/hooks/
	cat <<-EOF | tee $mountpoint/etc/pacman.d/hooks/mirrorupgrade.hook
		[Trigger]
		Operation = Upgrade
		Type = Package
		Target = pacman-mirrorlist

		[Action]
		Description = Updating pacman-mirrorlist with reflector and removing pacnew...
		When = PostTransaction
		Depends = reflector
		Exec = /bin/sh -c "reflector --country '$selected_country' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist; rm -f /etc/pacman.d/mirrorlist.pacnew"
	EOF
}

install_bootloader()
{
	echo "## installing grub to ${DSK}"
	pacstrap $mountpoint grub 

	#/etc/machine-id 
	#uname -r
	#/etc/os-release

	if $enable_uefi ; then
		pacstrap $mountpoint dosfstools efibootmgr
		arch_chroot "grub-install --efi-directory=/boot/efi --target=x86_64-efi --bootloader-id=grub_uefi --recheck"
	else
		pacstrap $mountpoint memtest86+ 
		arch_chroot "grub-install --target=i386-pc --recheck ${DSK}"
	fi

	if $enable_luks ; then
		cryptdevice="cryptdevice=$partroot:$maproot"

		if $enable_trim ; then 
			echo "## appending allow-discards for TRIM support"
			cryptdevice+=":allow-discards"
		fi
		sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$#$cryptdevice\"#" $mountpoint/etc/default/grub
		sed -i -e "s/#GRUB_DISABLE_LINUX_UUID/GRUB_DISABLE_LINUX_UUID/" $mountpoint/etc/default/grub
	fi

	if ! grep -q "GRUB_DISABLE_SUBMENU=y" $mountpoint/etc/default/grub ; then
		echo -e "\nGRUB_DISABLE_SUBMENU=y" | sudo tee --append $mountpoint/etc/default/grub
	fi

	echo "## printing /etc/default/grub"
	cat $mountpoint/etc/default/grub

	echo "## generating /boot/grub/grub.cfg"
	arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

	if $enable_luks ; then
		echo "## printing cryptdevice line from /boot/grub/grub.cfg"
		cat $mountpoint/boot/grub/grub.cfg | grep -m 1 "cryptdevice"
	fi
}

create_user() {
	echo "## adding user: $username"
	pacstrap $mountpoint sudo
	arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage,optical -s /bin/bash $username"

	echo "## setting password for user $username"
	arch_chroot "printf \"$userpass\n$userpass\" | passwd $username"

	echo "## allowing wheel group as sudoers"
	sed -i '/%wheel ALL=(ALL) ALL/s/^#//' $mountpoint/etc/sudoers

	echo "export EDITOR=\"nano\"" >> $mountpoint/home/$username/.bashrc
}

install_network_daemon() {
	enable_networkmanager=false
	if [ $setup_network == "networkmanager" ] ; then
			echo "## installing NetworkManager"
			pacstrap $mountpoint networkmanager
			arch_chroot "systemctl enable NetworkManager && systemctl enable NetworkManager-dispatcher.service"
			enable_networkmanager=true
	elif [ $setup_network == "networkd" ] ; then
			echo "## enabling systemd-networkd"
			arch_chroot "systemctl enable systemd-networkd.service"
			echo "## read https://wiki.archlinux.org/index.php/Systemd-networkd for configuration"
	fi
}

enable_ntpd() {
	if $enable_ntpd ; then
		echo "## enabling network time daemon"
		pacstrap $mountpoint ntp

		if $enable_networkmanager ; then
			pacstrap $mountpoint networkmanager-dispatcher-ntpd
		fi

		arch_chroot "ntpd -q"
		#arch_chroot "hwclock -w"
		arch_chroot "systemctl enable ntpd.service"
	fi
}

enable_sshd() {
	if $enable_sshd ; then
		pacstrap $mountpoint openssh
		arch_chroot "systemctl enable sshd.service"
	fi
}

paccache_cleanup() {
	pacstrap $mountpoint pacman-contrib

	cat <<-'EOF' | tee $mountpoint/etc/systemd/system/paccache-clean.timer
		[Unit]
		Description=Clean pacman cache weekly

		[Timer]
		OnBootSec=10min
		OnCalendar=weekly
		Persistent=true     
		 
		[Install]
		WantedBy=timers.target
	EOF

	cat <<-'EOF' | tee $mountpoint/etc/systemd/system/paccache-clean.service
		[Unit]
		Description=Clean pacman cache

		[Service]
		Type=oneshot
		ExecStart=/usr/bin/paccache -rk2
		ExecStart=/usr/bin/paccache -ruk0
	EOF

	arch_chroot "systemctl enable paccache-clean.timer"
}

install_aur_helper() {
	if $install_aur ; then
		echo "## Installing yay AUR Helper"
		pacstrap $mountpoint base-devel git

		sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' $mountpoint/etc/sudoers
		arch_chroot "sudo su $USER_NAME -c \" \
		mkdir -p /home/$USER_NAME/.cache/yay && \
		cd /home/$USER_NAME/.cache/yay && \
		git clone https://aur.archlinux.org/yay.git && \
		cd yay && \
		makepkg -si --noconfirm\""
		sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' $mountpoint/etc/sudoers

		echo "Defaults passwd_timeout=0" | tee $mountpoint/etc/sudoers.d/timeout
		echo 'Defaults editor=/usr/bin/nano, !env_editor' | tee $mountpoint/etc/sudoers.d/nano
	fi
}

install_video_drivers() {
	#TODO : FIX THIS

	case $(whiptail --menu "Choose a video driver" 20 60 12 \
	"1" "vesa (generic)" \
	"2" "virtualbox" \
	"3" "Intel" \
	"5" "AMD" \
	"6" "NVIDIA (nouveau)" \
	3>&1 1>&2 2>&3) in
		1)
			echo "## installing vesa"
			pacstrap $mountpoint xf86-video-vesa
		;;
		2)
			echo "## installing virtualbox"
			pacstrap $mountpoint virtualbox-guest-utils
		;;
		3)
			echo "## installing intel"
			pacstrap $mountpoint xf86-video-intel vulkan-intel
			#if [[ `uname -m` == x86_64 ]]; then
			#	pacstrap $mountpoint lib32-intel-dri
			#fi
		;;
    	5)
			echo "## installing AMD"
			pacstrap $mountpoint xf86-video-ati
			#if [[ `uname -m` == x86_64 ]]; then
			#	pacstrap $mountpoint lib32-ati-dri
			#fi
		;;
		6)
			echo "## installing NVIDIA open-source (nouveau)"
			pacstrap $mountpoint xf86-video-nouveau
			#if [[ `uname -m` == x86_64 ]]; then
			#	pacstrap $mountpoint lib32-nouveau-dri
			#fi
		;;
	esac
}

install_desktop_environment() {
	#TODO : FIX THIS

	pacstrap $mountpoint xorg-server xorg-xinit mate mate-extra pulseaudio network-manager-applet gnome-icon-theme

	echo "exec mate-session" > $mountpoint/home/$username/.xinitrc

	echo "Settings lock-screen background image to solid black"
	cat <<-'EOF' | tee /usr/share/glib-2.0/schemas/mate-background.gschema.override
		[org.mate.background]
		color-shading-type='solid'
		picture-options='scaled'
		picture-filename=''
		primary-color='#000000'
	EOF
	glib-compile-schemas /usr/share/glib-2.0/schemas/

	echo "fixing mate-menu icon for gnome icon theme"
	sudo wget -O /usr/share/pixmaps/arch-menu.png http://i.imgur.com/vBpJDs7.png
	gsettings set org.mate.panel.menubar icon-name arch-menu

	#yay -S --noconfirm adwaita-x-dark-and-light-theme

	echo "## Installing Fonts"
	pacstrap $mountpoint ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
	if ! test -f /etc/fonts/conf.d/70-no-bitmaps.conf ; then sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/ ; fi

	if whiptail --yesno "enable autologin for user: $username?" 8 40 ; then
		echo "## enabling autologin for user: $username"
		sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
		echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" \
			| sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf
	fi

	echo "## Installing X Autostart"
	if ! grep -q "exec startx" ~/.bash_profile ; then 
		test -f /home/$username/.bash_profile || cp /etc/skel/.bash_profile ~/.bash_profile
		echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> ~/.bash_profile
	fi

	if ! grep -q "complete -cf sudo" ~/.bashrc ; then 
		echo "complete -cf sudo" >> ~/.bashrc
	fi
	if ! grep -q "bash_aliases" ~/.bashrc ; then 
		echo -e "if [ -f ~/.bash_aliases ]; then\n. ~/.bash_aliases\nfi" >> ~/.bashrc
	fi
	if ! grep -q "yolo" ~/.bash_aliases ; then 
		echo "alias generate-playlist='ls -1 *.mp3 > \"\${PWD##*/}\".m3u'" >> ~/.bash_aliases
	fi

	# steam syncthing
	sudo pacman -S firefox vlc geary openssh sshfs
	sudo pacman -S ntfsprogs rsync p7zip unrar zip gparted
	sudo pacman -S gimp youtube-dl tmux inkscape
	sudo pacman -S exfat-utils fuse-exfat dosfstools
	sudo pacman -S libreoffice-fresh brasero keepassxc

	sudo pacman -S gvfs-mtp libmtp android-tools android-udev heimdall
	sudo gpasswd -a `whoami` uucp
	sudo gpasswd -a `whoami` adbusers

	sudo pacman -S docker
	sudo gpasswd -a `whoami` docker
	sudo systemctl start docker.service
	sudo systemctl enable docker.service

	# virtualbox
}

finish_setup() {
	#TODO: offer to umount | reboot | poweroff | do nothing
	if whiptail --yesno "Reboot now?" 8 40 ; then
		echo "## unmounting and rebooting"

		if $enable_uefi ; then
			umount -l $mountpoint/boot/efi
		fi
		umount -l $mountpoint/boot
		umount -l $mountpoint

		if $enable_luks ; then
			cryptsetup luksClose $maproot
		fi

		reboot
	fi
}


check_net_connectivity
set_variables
update_locale
update_mirrorlist
partition_disk
format_disk
update_mirrorlist_reflector
install_base
configure_fstab
configure_system
install_bootloader
create_user
install_network_daemon
enable_ntpd
enable_sshd
paccache_cleanup
install_aur_helper
#finish_setup
