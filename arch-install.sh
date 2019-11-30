#!/bin/bash

set -e
command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }

check_net_connectivity() {
	echo "## checking net connectivity"
	ping -c 2 resolver1.opendns.com
	# TODO : offer wifimenu ?

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
	# cat /etc/locale.gen | grep -oP "^#\K[a-zA-Z0-9@._-]+"
	locale=$(whiptail --nocancel --inputbox "Set locale:" 10 40 "en_AU.UTF-8" 3>&1 1>&2 2>&3)

	keyboard=$(whiptail --nocancel --inputbox "Set keyboard:" 10 40 "us" 3>&1 1>&2 2>&3)

	selected_timezone=$(tzselect)

	new_uuid=$(cat /sys/devices/virtual/dmi/id/product_serial)
	hostname=$(whiptail --nocancel --inputbox "Set hostname:" 10 40 "arch-$new_uuid" 3>&1 1>&2 2>&3)

	# TODO : don't offer UEFI if not present
	# [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
	enable_uefi=false
	if whiptail --defaultno --yesno "install for UEFI system?" 8 40 ; then
		enable_uefi=true
	fi

	enable_lts=false
	if whiptail --defaultno --yesno "install linux-lts kernel (long term support)?" 8 40 ; then
		enable_lts=true
	fi

	create_user=false
	if whiptail --yesno "create a user for this installation?" 8 40 ; then
		create_user=true
		username=$(whiptail --nocancel --inputbox "Set username:" 10 40 "$new_uuid" 3>&1 1>&2 2>&3)
		userpass=$(whiptail --nocancel --passwordbox "Set password:" 10 40 3>&1 1>&2 2>&3)
	fi

	setup_network=false
	case $(whiptail --menu "Choose a network daemon" 20 60 12 \
	"1" "NetworkManager" \
	"2" "systemd-networkd" \
	"3" "None" \
	3>&1 1>&2 2>&3) in
		1)
			setup_network="networkmanager"
		;;
		2)
			setup_network="networkd"
		;;
	esac

	enable_ntpd=false
	enable_sshd=false
	if [ $setup_network != false ] ; then
		if whiptail --defaultyes --yesno "enable network time daemon?" 8 40 ; then
			enable_ntpd=true
		fi

		if whiptail --defaultno --yesno "enable ssh daemon?" 8 40 ; then
			enable_sshd=true
		fi
	fi

	install_aur=false
	if whiptail --defaultno --yesno "install AUR helper (yay)?" 8 40 ; then
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

	enable_gpt=true
	if ! $enable_uefi ; then
		if ! whiptail --defaultno --yesno "use GPT partitioning?" 8 40 ; then
			enable_gpt=false
		fi
	fi

	enable_swap=false
	if whiptail --defaultno --yesno "create a swap partition?" 8 40 ; then
		enable_swap=true
	fi

	labelroot="arch-root"
	labelboot="arch-boot"

	if $enable_swap ; then
		labelswap="arch-swap"
		# TODO : 512 unless memsize < 512
		swap_size=`awk '/MemTotal/ {printf( "%.0f\n", $2 / 1000 )}' /proc/meminfo`
		swap_size=$(whiptail --nocancel --inputbox "Set swap partition size \n(recommended based on meminfo):" 10 40 "$swap_size" 3>&1 1>&2 2>&3)
	fi

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

	boot_size=$(whiptail --nocancel --inputbox "Set boot partition size:" 10 40 "500" 3>&1 1>&2 2>&3)
	boot_end=$(( ${esp_end} + ${boot_size} ))

	if $enable_swap ; then
		swap_end=$(( $boot_end + ${swap_size} ))
	fi

	if $enable_gpt ; then
		partroot="/dev/disk/by-partlabel/$labelroot"
		partswap="/dev/disk/by-partlabel/$labelswap"
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

		if $enable_swap ; then
			echo "## creating partition $labelswap"
			parted -s ${DSK} -a optimal unit MB mkpart primary linux-swap $boot_end $swap_end
			parted -s ${DSK} name 3 $labelswap

			echo "## creating partition $labelroot"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary $swap_end -1
			parted -s ${DSK} name 4 $labelroot
		else
			echo "## creating partition $labelroot"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary $boot_end -1
			parted -s ${DSK} name 3 $labelroot
		fi
	else
		parted -s ${DSK} mklabel msdos

		echo "## creating partition $labelboot"
		parted -s ${DSK} -a optimal unit MB mkpart primary ${esp_end} $boot_end
		partboot="${DSK}1"

		if $enable_swap ; then
			echo "## creating partition $labelswap"
			parted -s ${DSK} -a optimal unit MB mkpart primary linux-swap $boot_end $swap_end
			partswap="${DSK}2"

			echo "## creating partition $labelroot"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary $swap_end -1
			partroot="${DSK}3"
		else
			echo "## creating partition $labelroot"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary $boot_end -1
			partroot="${DSK}2"
		fi
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
	if whiptail --defaultno --yesno "encrypt disk with dm-crypt (kernel transparent disk encryption)?" 8 40 ; then
		enable_luks=true
	fi

	enable_bcache=false
	#if ! $enable_luks ; then
		# TODO : revamp bcache setup - hasn't been tested in a few years
		#if whiptail --defaultno --yesno "setup bcache?" 8 40 ; then
		#	enable_bcache=true
		#fi
	#fi

	if $enable_bcache ; then
		pacman -Sy --noconfirm git
		# TODO : don't fail if nothing to install
		fgrep -vf <(pacman -Qq) <(pacman -Sgq base-devel) | xargs pacman -S --noconfirm gcc
		export EDITOR=nano
		curl https://aur.archlinux.org/cgit/aur.git/snapshot/bcache-tools.tar.gz | tar -zx --directory=/tmp
		pushd /tmp/bcache-tools
		chown -R nobody .
		sudo -u nobody makepkg --noconfirm
		pacman -U bcache-tools*.pkg.tar.xz
		popd
		modprobe bcache
		CACHEDSK=$(whiptail --nocancel --menu "Select the Disk to use as cache" 18 45 10 $disks 3>&1 1>&2 2>&3)
		sgdisk --zap-all ${CACHEDSK}
		wipefs -a ${CACHEDSK}
		wipefs -a ${partroot}
		make-bcache --wipe-bcache -B ${partroot} -C ${CACHEDSK}
		sleep 4
		partroot="/dev/bcache0"
	fi

	if $enable_luks ; then
		maproot="croot"
		mapswap="cswap"

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

		if $enable_swap ; then
			mkswap $partswap
			swapon $partswap
		fi
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

update_mirrorlist_reflector() {
	# TODO
	# /etc/pacman.d/hooks/mirrorupgrade.hook

	pacstrap $mountpoint reflector

	shopt -s lastpipe
	reflector --list-countries | \
	sed 's/[0-9]*//g;s/\(.*\)\([A-Z][A-Z]\)/\2\n\1/g' | \
	readarray countries
	selected_country=$(whiptail --nocancel --menu "select mirrorlist country:" 30 78 22 "${countries[@]}" 3>&1 1>&2 2>&3)

	reflector -c $selected_country -l 5 --sort rate --save /etc/pacman.d/mirrorlist
}

install_base(){
	pacman-key --refresh-keys
	echo "## installing base system"
	pacstrap $mountpoint base 
	if ! $enable_lts ; then
		pacstrap $mountpoint linux linux-firmware
	else
		pacstrap $mountpoint linux-lts linux-lts-headers linux-firmware
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

	if $enable_swap ; then
		if $enable_luks ; then
			echo "$mapswap $partswap /dev/urandom swap,cipher=aes-xts-plain:sha256,size=256" >> $mountpoint/etc/crypttab
			echo "/dev/mapper/$mapswap none swap defaults 0 0" >> $mountpoint/etc/fstab
		fi
	fi

	if $enable_trim ; then
		echo "## adding trim support"
		sed -i -e 's/defaults/defaults,discard/' $mountpoint/etc/fstab

		if $enable_luks ; then
			sed -i -e 's/rw,/discard,rw,/' $mountpoint/etc/fstab
			if $enable_swap ; then
				sed -i -e 's/swap,/swap,discard,/' $mountpoint/etc/crypttab
			fi
		fi
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

	if $enable_bcache ; then
		cp /tmp/bcache-tools/*.pkg.tar.xz $mountpoint/var/cache/pacman/pkg/
		arch_chroot "pacman -U /var/cache/pacman/pkg/bcache-tools* --noconfirm"
		echo "## adding bcache hook"
		sed -i -e "/^HOOKS/s/filesystems/bcache filesystems/" $mountpoint/etc/mkinitcpio.conf
		sed -i -e '/^MODULES/s/""/"bcache"/' $mountpoint/etc/mkinitcpio.conf
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

	arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

	#if $enable_luks ; then
	#	whiptail --title "check cryptdevice in grub.cfg" --msgbox "`cat $mountpoint/boot/grub/grub.cfg | grep -m 1 "cryptdevice"`" 20 80
	#fi
}

create_user() {
	if $create_user ; then
		echo "## adding user: $username"
		pacstrap $mountpoint sudo
		arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage,optical -s /bin/bash $username"
		echo "## setting password for user $username"
		arch-chroot $mountpoint "printf \"$userpass\n$userpass\" | passwd $username"
		sed -i '/%wheel ALL=(ALL) ALL/s/^#//' $mountpoint/etc/sudoers

		if ! grep -q "EDITOR" $mountpoint/home/$username/.bashrc ; then 
			echo "export EDITOR=\"nano\"" >> $mountpoint/home/$username/.bashrc
		fi
	fi
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

		#gpg --list-keys
		#if [ ! -f ~/.gnupg/gpg.conf ] ; then
		#	echo "keyserver-options auto-key-retrieve" > ~/.gnupg/gpg.conf
		#else
		#	sed -i -e "/^#keyserver-options auto-key-retrieve/s/#//" ~/.gnupg/gpg.conf
		#fi

		curl https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz | tar -zx --directory=/tmp
		pushd /tmp/yay
		chown -R nobody .
		sudo -u nobody makepkg --noconfirm
		popd
		cp /tmp/yay/*.pkg.tar.xz $mountpoint/var/cache/pacman/pkg/
		arch_chroot "pacman -U /var/cache/pacman/pkg/yay* --noconfirm"

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
			if [[ `uname -m` == x86_64 ]]; then
				pacstrap $mountpoint lib32-intel-dri
			fi
		;;
    	5)
			echo "## installing AMD"
			pacstrap $mountpoint xf86-video-ati
			if [[ `uname -m` == x86_64 ]]; then
				pacstrap $mountpoint lib32-ati-dri
			fi
		;;
		6)
			echo "## installing NVIDIA open-source (nouveau)"
			pacstrap $mountpoint xf86-video-nouveau
			if [[ `uname -m` == x86_64 ]]; then
				pacstrap $mountpoint lib32-nouveau-dri
			fi
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
	sudo pacman -S firefox vlc geary openssh 
	sudo pacman -S ntfsprogs rsync p7zip unrar zip gparted
	sudo pacman -S gimp youtube-dl tmux screenfetch	
	sudo pacman -S exfat-utils fuse-exfat dosfstools
	sudo pacman -S libreoffice-fresh brasero

	sudo pacman -S gvfs-mtp libmtp android-tools android-udev heimdall
	sudo gpasswd -a `whoami` uucp
	sudo gpasswd -a `whoami` adbusers
}

install_docker() {
	sudo pacman -S docker
	sudo gpasswd -a `whoami` docker
	sudo systemctl start docker.service
	sudo systemctl enable docker.service
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
