#!/bin/bash

set -e
command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }
# TODO : log all output

check_net_connectivity() {
	echo "## checking net connectivity"
	ping -c 2 archlinux.org

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
}

set_variables() {
	echo "## defining variables for installation"

	selected_keymap="us"
	if whiptail --defaultno --yes-button "Change Keymap" \
		--no-button "Accept" \
		--yesno "The default console keymap is 'US'" 7 55 ; then
			shopt -s lastpipe
			localectl list-keymaps | sed 's/$/\n/g' | readarray -t keymap_array
			selected_keymap=$(whiptail --noitem --default-item 'us' --nocancel \
				--menu "select a keymap:" 30 50 22 "${keymap_array[@]}" 3>&1 1>&2 2>&3)
	fi
	loadkeys $selected_keymap

	selected_locale="en_US.UTF-8"
	if whiptail --defaultno --yes-button "Change Locale" \
		--no-button "Accept" \
		--yesno "The default locale is 'en_US.UTF-8'" 7 55 ; then
			sed -i "s/en_US.UTF-8/#en_US.UTF-8/" /etc/locale.gen
			shopt -s lastpipe
			cat /etc/locale.gen | grep "UTF-8" | grep -oP "^[#]?\K[a-zA-Z0-9@._-]+" | sed 's/$/\n/g' | readarray -t locale_array
			selected_locale=$(whiptail --noitem --default-item 'en_AU.UTF-8' --nocancel \
				--menu "select a UTF-8 locale:" 30 50 22 "${locale_array[@]}" 3>&1 1>&2 2>&3)
	fi
	export LANG=$selected_locale
	sed -i -e "s/#$selected_locale/$selected_locale/" /etc/locale.gen
	locale-gen

	selected_timezone=$(tzselect)

	#TODO : user machine id as default hostname
	#new_uuid=$(cat /sys/devices/virtual/dmi/id/product_serial) # or board_name
	hostname=$(whiptail --nocancel --inputbox "Set hostname:" 10 40 "arch-box" 3>&1 1>&2 2>&3)

	enable_uefi=false
	if [ -d /sys/firmware/efi ] ; then
		if whiptail --yesno "Detected booted in UEFI mode\nInstall for UEFI system?" 8 40 ; then
			enable_uefi=true
		fi
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
		# TODO : warn hibernation is not available with systemd-swap
		# TODO : offer zswap + swapfc or only ZRam (for SSD wear)
	fi

	install_aur=false
	if whiptail --defaultno --yesno "Install AUR helper (yay) to access the\narch user community-driven repository\n(which includes non-FOSS software)" 10 60 ; then
		install_aur=true
	fi

	install_kernel=$(whiptail --nocancel --menu "Choose a kernel:" 18 100 10 \
			linux "Stable — Vanilla Linux kernel and modules" \
			linux-hardened "security-focused kernel (patches to mitigate kernel & userspace exploits)" \
			linux-lts "Long-term support (LTS)" \
			linux-zen "Collaborative patches via kernel hackers to provide for everyday systems" \
		3>&1 1>&2 2>&3 )

	install_desktop=false
	if whiptail --defaultno --yesno "Install Desktop Environment?" 8 40 ; then
		install_desktop=$(whiptail --nocancel --menu "Choose a desktop environment:" 18 70 10 \
			mate "MATE Desktop Environment is the continuation of GNOME 2" \
			xfce "Xfce is a lightweight desktop environment" \
			gnome "GNOME Project open-source desktop environment" \
		3>&1 1>&2 2>&3 )

		install_driver=$(whiptail --nocancel --menu "Choose a video driver:" 18 60 10 \
			xf86-video-vesa "vesa (generic)" \
			virtualbox-guest-utils "virtualbox" \
			xf86-video-intel "Intel" \
			xf86-video-amdgpu "AMDGPU" \
			xf86-video-ati "ATI (old cards)" \
			xf86-video-nouveau "NVIDIA (nouveau opensource)" \
		3>&1 1>&2 2>&3 )

		install_packages=$(whiptail --nocancel \
		--checklist "Choose software to be added:" 22 80 16 \
			libreoffice-fresh "Free office suite" off \
			brasero "CD/DVD mastering tool" off \
			steam "Valves game delivery client" off \
			steam-native-runtime "Native replacement for Steam runtime" off \
			syncthing "Continuous network file synchronization" off \
			keepassxc "Keepass password manager" off \
			docker "run lightweight application containers" off \
			virtualbox "x86 virtualization" off \
			android-tools "Android platform tools" on \
			android-udev "Udev rules to connect Android devices" on \
			gvfs-mtp "mount android MTP devices" on \
			libmtp "library for android MTP" on \
			heimdall "Flash firmware (ROMs) onto Samsung Phones" off \
			firefox "Standalone web browser from mozilla.org" on \
			thunderbird "mail and news reader from mozilla.org" on \
			hexchat "graphical IRC (chat) client" off \
			geary "Lightweight email client" off \
			vlc "Media Player" on \
			rhythmbox "Music Player" off \
			calibre "Ebook management application" off \
			simple-scan "Simple scanning utility" off \
			qcad "2D CAD drawing tool" off \
			p7zip "7z archive support" on \
			unrar "rar archive support" on \
			zip "zip archive support" on \
			gimp "GNU Image Manipulation Program" on \
			inkscape "vector graphics editor" on \
			youtube-dl "youtube downloader" on \
			tmux "terminal multiplexer" on \
			rsync "synchronizing files between systems" on \
			gparted "GNOME Partition Editor" on \
			ntfsprogs "ntfs filesystem support" on \
			exfat-utils "exfat filesystem support" on \
			dosfstools "vfat/fat filesystem support" on \
			openssh "remote login via SSH protocol" on \
			sshfs "FUSE client for SSH File Transfers" on \
			wget "Network utility to retrieve files" on \
			networkmanager-openvpn "NetworkManager VPN plugin for OpenVPN" on \
		3>&1 1>&2 2>&3 )

		install_login=$(whiptail --nocancel --menu "Choose a login method:" 18 70 10 \
			autologin "passwordless auto-login straight to desktop" \
			lightdm "Lightweight display manager" \
			gdm "GNOME Display Manager" \
			none "Select for Headless/Server" \
		3>&1 1>&2 2>&3 )
	fi
}

partition_disk() {
	disks=`parted --list --script | awk -F ": |, |Disk | " '/Disk \// { print $2" "$3$4 }'`
	DSK=$(whiptail --nocancel --menu "Select the Disk to install to" 18 45 10 $disks 3>&1 1>&2 2>&3)

	echo "## WILL COMPLETELY WIPE ${DSK}"
	echo "## ARE YOU SURE ???"
	read -p "Press [Enter] key to continue"
	sgdisk --zap-all ${DSK}

	enable_trim=false
	if [ -n "$(hdparm -I ${DSK} 2>&1 | grep 'TRIM supported')" ]; then
		echo "## detected TRIM support"
		enable_trim=true
	fi

	enable_gpt=false
	if $enable_uefi ; then
		if whiptail --yesno "use GPT partitioning?\n(It is recommended to always use GPT for UEFI boot)" 8 60 ; then
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
	mirrorlist_url="https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4"

	mirrorlist_tmp=$(mktemp --suffix=-mirrorlist)
	curl -so ${mirrorlist_tmp} ${mirrorlist_url}

	if [[ -s ${mirrorlist_tmp} ]]; then
		shopt -s lastpipe
		tail -n +7  ${mirrorlist_tmp} | grep -oP "^## \K[a-zA-Z ]+" | sed 's/$/\n/g' | readarray countries
		selected_country=$(whiptail --nocancel --menu "select mirrorlist country:" 30 78 22 "${countries[@]}" 3>&1 1>&2 2>&3)
		sed -i -n "/## $selected_country/,/^\$/p" ${mirrorlist_tmp}
		sed -i 's/^#Server/Server/g' ${mirrorlist_tmp}

		mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig &&
		mv ${mirrorlist_tmp} /etc/pacman.d/mirrorlist
		chmod +r /etc/pacman.d/mirrorlist
	else
		echo "## could not download mirrorlist"
		echo "Server=https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
	fi
}

install_mirrorlist_reflector_hook() {
	pacstrap $mountpoint reflector

	arch-chroot $mountpoint reflector -c $selected_country -l 5 --sort rate --save /etc/pacman.d/mirrorlist

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

install_base(){
	pacman-key --refresh-keys
	echo "## installing base system"
	pacstrap $mountpoint base $install_kernel linux-firmware

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq intel` ; then
		echo "## installing intel ucode"
		pacstrap $mountpoint intel-ucode
	fi

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq amd` ; then
		echo "## installing amd ucode"
		pacstrap $mountpoint amd-ucode
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
	sed -i -e "s/#$selected_locale/$selected_locale/" $mountpoint/etc/locale.gen
	arch_chroot "locale-gen"
	echo LANG=$selected_locale > $mountpoint/etc/locale.conf
	arch_chroot "export LANG=$selected_locale"

	if $enable_luks ; then
		echo "## adding encrypt hook"
		sed -i -e "/^HOOKS/s/filesystems/encrypt filesystems/" $mountpoint/etc/mkinitcpio.conf
		arch_chroot "mkinitcpio -p linux"
	fi

	echo "## writing vconsole.conf"
	echo "KEYMAP=$selected_keymap" > $mountpoint/etc/vconsole.conf
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

		mkdir -p $mountpoint/etc/systemd/swap.conf.d/
		echo -e "swapfc_enabled=1\n" \
			| tee $mountpoint/etc/systemd/swap.conf.d/override.conf

		# TODO : offer zram only for SSD drives
		#zswap_enabled=0
		#zram_enabled=1
		#swapfc_enabled=0

		arch_chroot "systemctl enable systemd-swap"

		echo vm.swappiness=5 | tee -a $mountpoint/etc/sysctl.d/99-sysctl.conf
		echo vm.vfs_cache_pressure=50 | tee -a $mountpoint/etc/sysctl.d/99-sysctl.conf
	fi

	if [[ `uname -m` == x86_64 ]]; then
		echo "## x86_64 detected, adding multilib repository"
		sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' $mountpoint/etc/pacman.conf
		#pacman -Syy
	fi
}

install_bootloader()
{
	# TODO : offer systemd-boot

	echo "## installing grub to ${DSK}"
	pacstrap $mountpoint grub 

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
	pacstrap $mountpoint sudo nano
	arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage,optical -s /bin/bash $username"

	echo "## setting password for user $username"
	arch_chroot "printf \"$userpass\n$userpass\" | passwd $username"

	echo "## allowing members of wheel group as sudoers"
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
	echo "## enabling network time daemon"
	pacstrap $mountpoint ntp

	if $enable_networkmanager ; then
		pacstrap $mountpoint networkmanager-dispatcher-ntpd
	fi

	arch_chroot "ntpd -q"
	#arch_chroot "hwclock -w"
	arch_chroot "systemctl enable ntpd.service"
}

enable_sshd() {
	pacstrap $mountpoint openssh
	arch_chroot "systemctl enable sshd.service"
}

paccache_cleanup() {
	echo "## adding weekly timer to cleanup pacman pkg cache"
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
	echo "## Installing yay AUR Helper"
	pacstrap $mountpoint base-devel git

	sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' $mountpoint/etc/sudoers
	arch_chroot "sudo su $username -c \" \
	mkdir -p /home/$username/.cache/yay && \
	cd /home/$username/.cache/yay && \
	git clone https://aur.archlinux.org/yay.git && \
	cd yay && \
	makepkg -si --noconfirm\""
	sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' $mountpoint/etc/sudoers

	echo "Defaults passwd_timeout=0" | tee $mountpoint/etc/sudoers.d/timeout
	echo 'Defaults editor=/usr/bin/nano, !env_editor' | tee $mountpoint/etc/sudoers.d/nano
}

install_desktop_environment() {
	pacstrap $mountpoint xorg-server xorg-xinit pulseaudio 

	if [ $install_desktop == "mate" ] ; then
		pacstrap $mountpoint mate mate-extra network-manager-applet gnome-icon-theme
	elif [ $install_desktop == "gnome" ] ; then
		pacstrap $mountpoint gnome gnome-extra
	elif [ $install_desktop == "xfce" ] ; then
		pacstrap $mountpoint xfce4 xfce4-goodies
	fi

	pacstrap $mountpoint mesa $install_driver

	if [ $install_driver == "xf86-video-intel" ] ; then
		pacstrap $mountpoint vulkan-icd-loader vulkan-intel intel-media-driver
	elif [ $install_driver == "xf86-video-amdgpu" ] ; then
		pacstrap $mountpoint vulkan-icd-loader vulkan-radeon libva-mesa-driver
	elif [ $install_driver == "xf86-video-ati" ] ; then
		pacstrap $mountpoint mesa-vdpau
	elif [ $install_driver == "xf86-video-nouveau" ] ; then
		pacstrap $mountpoint libva-mesa-driver
	fi

	if [[ "${install_packages[@]}" =~ "virtualbox" ]]; then
		host_modules_pkg="virtualbox-host-modules-arch"
		if [ $install_kernel != "linux" ] ; then
			host_modules_pkg="virtualbox-host-dkms $install_kernel-headers"
		fi
		pacstrap $mountpoint virtualbox $host_modules_pkg virtualbox-guest-iso
		arch-chroot $mountpoint usermod -a -G vboxusers $username
	fi

	pacstrap $mountpoint $(eval echo ${install_packages[@]})

	if [[ "${install_packages[@]}" =~ "android-tools" ]]; then
		arch-chroot $mountpoint usermod -a -G uucp,adbusers $username
	fi

	if [[ "${install_packages[@]}" =~ "docker" ]]; then
		arch-chroot $mountpoint usermod -a -G docker $username
		arch-chroot $mountpoint systemctl enable docker.service
	fi

	if [ $install_login == "autologin" ] ; then
		echo "## enabling autologin for user: $username"
		mkdir -p $mountpoint/etc/systemd/system/getty@tty1.service.d
		echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" \
			| tee $mountpoint/etc/systemd/system/getty@tty1.service.d/autologin.conf
		echo "## Enabling Xorg Autostart"
		echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> $mountpoint/home/$username/.bash_profile
		
		if [ $install_desktop == "mate" ] ; then
			echo "exec mate-session" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "gnome" ] ; then
			echo -e "export XDG_SESSION_TYPE=x11\nexport GDK_BACKEND=x11\nexec gnome-session" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "xfce" ] ; then
			echo "exec startxfce4" > $mountpoint/home/$username/.xinitrc
		fi		
		arch_chroot "chown -R $username:users /home/$username"
	elif [ $install_login == "lightdm" ] ; then
		pacstrap $mountpoint lightdm lightdm-gtk-greeter
		arch_chroot "systemctl enable lightdm.service"
	elif [ $install_login == "gdm" ] ; then
		pacstrap $mountpoint gdm
		arch_chroot "systemctl enable gdm.service"
	fi

	echo "## Installing Fonts"
	pacstrap $mountpoint ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
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

function main() {
	check_net_connectivity
	set_variables
	update_mirrorlist
	partition_disk
	format_disk
	install_base
	configure_fstab
	configure_system
	install_bootloader
	create_user
	install_network_daemon
	if $enable_ntpd ; then
		enable_ntpd
	fi
	if $enable_sshd ; then
		enable_sshd
	fi
	paccache_cleanup
	if $install_aur ; then
		install_aur_helper
	fi
	if [ $install_desktop != false ] ; then
		install_desktop_environment
	fi
	install_mirrorlist_reflector_hook
	finish_setup
}

main
