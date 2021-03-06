#!/bin/bash

set -e
command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }
# TODO : log all output

export NEWT_COLORS='root=,black'
GREEN=$(tput setaf 2)
BLACK=$(tput sgr0)

check_net_connectivity() {
	echo "${GREEN}## checking net connectivity${BLACK}"
	ping -c 2 archlinux.org

	# TODO : offer wifimenu ?

	# TODO : check default gateway is set?
	#ip route add default via <gw-ip>

	echo "${GREEN}## ensuring the system clock is accurate${BLACK}"
	timedatectl set-ntp true
}

enable_ssh() {
	systemctl start sshd
	ipaddr=`ip addr | grep inet | grep -e enp -e wlan | awk '{print $2}' | cut -d "/" -f1`
	echo "${GREEN}## set passwd for login with ssh root@$ipaddr${BLACK}"
	passwd
}

set_variables() {
	echo "${GREEN}## defining variables for installation${BLACK}"

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

	echo "${GREEN}## PLEASE SELECT YOUR TIMEZONE${BLACK}"
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

	# TODO : confirm not blank
	username=$(whiptail --nocancel --inputbox "Set username for sudo user to be created for this install" 10 40 3>&1 1>&2 2>&3)
	# TODO : confirm and compare password twice
	userpass=$(whiptail --nocancel --passwordbox "Set password for $username" 10 40 3>&1 1>&2 2>&3)

	# TODO : offer other network managers?
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
	if whiptail --yesno "Install AUR helper (yay) to access the\narch user community-driven repository\n(which includes non-FOSS software)" 10 60 ; then
		install_aur=true
	fi

	install_kernel=$(whiptail --nocancel --menu "Choose a kernel:" 18 100 10 \
			linux "Stable — Vanilla Linux kernel and modules" \
			linux-hardened "security-focused kernel (patches to mitigate kernel & userspace exploits)" \
			linux-lts "Long-term support (LTS)" \
			linux-zen "Collaborative patches via kernel hackers to provide for everyday systems" \
		3>&1 1>&2 2>&3 )

	enable_firejail=false
	if whiptail --defaultno --yesno "enable apparmor and firejail?\n(sandbox programs to harden the system)" 10 60 ; then
		enable_firejail=true
	fi

	#TODO : offer add zfs repo

	install_desktop=false
	if whiptail --yesno "Install Desktop Environment?" 8 40 ; then
		install_desktop=$(whiptail --nocancel --menu "Choose a desktop environment:" 18 70 10 \
			mate "MATE is the continuation of GNOME 2" \
			xfce "Xfce is a lightweight desktop environment" \
			kde "Plasma 5 fifth generation KDE environment" \
			budgie-desktop "default desktop of Solus OS, written from scratch" \
			gnome "GNOME Project open-source desktop environment" \
		3>&1 1>&2 2>&3 )

		install_driver=$(whiptail --nocancel --menu "Choose a video driver:" 18 60 10 \
			xf86-video-vesa "vesa (generic)" \
			virtualbox-guest-utils "virtualbox" \
			xf86-video-intel "Intel" \
			xf86-video-amdgpu "AMDGPU" \
			xf86-video-ati "ATI (old cards)" \
			nvidia "NVIDIA proprietary driver" \
			xf86-video-nouveau "NVIDIA (nouveau opensource)" \
		3>&1 1>&2 2>&3 )

		install_packages=$(whiptail --nocancel \
		--checklist "Choose software to be added:" 22 100 16 \
			libreoffice-fresh "Free office suite" off \
			brasero "CD/DVD mastering tool" off \
			steam "Valves game delivery client" off \
			steam-native-runtime "Native replacement for Steam runtime" off \
			discord "proprietary all-in-one voice and text chat application" off \
			syncthing "Continuous network file synchronization" off \
			keepassxc "Keepass password manager" off \
			docker "run lightweight application containers" off \
			virtualbox "x86 virtualization" off \
			wine "Compatibility layer for Windows programs" off \
			firefox "Standalone web browser from mozilla.org" on \
			chromium "open-source browser from Google" off \
			thunderbird "mail and news reader from mozilla.org" on \
			signal-desktop "Signal Private Messenger for Linux" off \
			hexchat "graphical IRC (chat) client" off \
			geary "Lightweight email client" off \
			vlc "Media Player" on \
			rhythmbox "GNOME Music Player" off \
			elisa "KDE Music Player" off \
			calibre "Ebook management application" off \
			gimp "GNU Image Manipulation Program" on \
			inkscape "vector graphics editor" on \
			intellij-idea-community-edition "Java IDE" off \
			networkmanager-openvpn "NetworkManager VPN plugin for OpenVPN" on \
			youtube-dl "youtube cli downloader" on \
			android-tools "Android platform tools" on \
			android-udev "Udev rules to connect Android devices" on \
			gvfs-mtp "mount android MTP devices" on \
			libmtp "library for android MTP" on \
			heimdall "Flash firmware (ROMs) onto Samsung Phones" off \
			simple-scan "Simple scanning utility" off \
			qcad "2D CAD drawing tool" off \
			p7zip "7z archive support" on \
			unrar "rar archive support" on \
			zip "zip archive support" on \
			tmux "terminal multiplexer" on \
			rsync "synchronizing files between systems" on \
			gparted "GNOME Partition Editor" on \
			ntfsprogs "ntfs filesystem support" on \
			exfat-utils "exfat filesystem support" on \
			dosfstools "vfat/fat filesystem support" on \
			openssh "remote login via SSH protocol" on \
			sshfs "FUSE client for SSH File Transfers" on \
			wget "Network utility to retrieve files" on \
		3>&1 1>&2 2>&3 )

		install_login=$(whiptail --nocancel --menu "Choose a login method:" 18 70 10 \
			autologin "passwordless auto-login straight to desktop" \
			lightdm "Lightweight display manager" \
			gdm "GNOME Display Manager" \
			sddm "KDE Display Manager" \
			none "Select for Headless/Server" \
		3>&1 1>&2 2>&3 )
	fi
}

partition_disk() {
	disks=`parted --list --script | awk -F ": |, |Disk | " '/Disk \// { print $2" "$3$4 }'`
	DSK=$(whiptail --nocancel --menu "Select the Disk to install to" 18 45 10 $disks 3>&1 1>&2 2>&3)

	enable_luks=false
	if whiptail --defaultno --yesno "encrypt entire disk with dm-crypt?\n(kernel transparent disk encryption)" 8 40 ; then
		enable_luks=true
		luks_keyfile=false
		encrypted_boot=false
		if whiptail --defaultno --yesno "encrypt grub /boot partition?\n(not recommended for dual-booting)" 8 40 ; then
			encrypted_boot=true
			if whiptail --yesno "Avoiding having to enter the passphrase twice?\n\nGRUB asks for a passphrase to unlock the LUKS1 encrypted partition, \
the partition unlock is not passed on to the initramfs. Hence, you have to enter the passphrase twice at boot: once for GRUB and once for \
the initramfs.\n\nAdd a keyfile embedded in the initramfs to avoid?" 16 60 ; then
				luks_keyfile=true
			fi
		fi
	fi

	echo "${GREEN}## WILL COMPLETELY WIPE ${DSK}${BLACK}"
	echo "${GREEN}## ARE YOU SURE ???${BLACK}"
	read -p "Press [Enter] key to continue"
	sgdisk --zap-all ${DSK}

	enable_trim=false
	if [ -n "$(hdparm -I ${DSK} 2>&1 | grep 'TRIM supported')" ]; then
		echo "${GREEN}## detected TRIM support${BLACK}"
		enable_trim=true
	fi

	labelroot="arch-root"
	
	if [ $enable_luks = true ] && [ $encrypted_boot = false ]  ; then
		labelboot="arch-boot"
		boot_size=200
	fi
	
	if [ $enable_uefi = true ] ; then
		parted -s ${DSK} mklabel gpt

		esp_end=501
		labelesp="arch-esp"
		partesp="/dev/disk/by-partlabel/$labelesp"
		
		echo "${GREEN}## creating EFI partition${BLACK}"
		parted -s ${DSK} -a optimal unit MB mkpart ESI 1 ${esp_end}
		parted -s ${DSK} set 1 boot on
		parted -s ${DSK} mkfs 1 fat32
		parted -s ${DSK} name 1 $labelesp
		
		if [ $enable_luks = true ] && [ $encrypted_boot = false ]  ; then
			boot_end=$(( ${esp_end} + ${boot_size} ))
			
			echo "${GREEN}## creating partition $labelboot${BLACK}"
			parted -s ${DSK} -a optimal unit MB mkpart primary ${esp_end} ${boot_end}
			parted -s ${DSK} name 2 $labelboot

			echo "${GREEN}## creating partition $labelroot${BLACK}"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary ${boot_end} -1
			parted -s ${DSK} name 3 $labelroot

			partboot="/dev/disk/by-partlabel/$labelboot"	
		else
			echo "${GREEN}## creating partition $labelroot${BLACK}"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary ${esp_end} -1
			parted -s ${DSK} name 2 $labelroot
		fi
		partroot="/dev/disk/by-partlabel/$labelroot"
	else
		parted -s ${DSK} mklabel msdos
		
		if [ $enable_luks = true ] && [ $encrypted_boot = false ]  ; then
			echo "${GREEN}## creating partition $labelboot${BLACK}"
			parted -s ${DSK} -a optimal unit MB mkpart primary 1 $boot_size
			partboot="${DSK}1"

			echo "${GREEN}## creating partition $labelroot${BLACK}"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary $boot_size -1
			partroot="${DSK}2"
		else
			echo "${GREEN}## creating partition $labelroot${BLACK}"
			parted -s ${DSK} -a optimal unit MB -- mkpart primary 1 -1
			partroot="${DSK}1"
		fi
		
	fi

	whiptail --title "generated partition layout" --msgbox "`parted -s ${DSK} print`" 20 70
}

format_disk() {
	mountpoint="/mnt"

	if [ $enable_luks = true ] ; then
		if [ $encrypted_boot = false ] ; then
			echo "${GREEN}## cleaning $partboot${BLACK}"
			wipefs -a $partboot
			echo "${GREEN}## mkfs $partboot${BLACK}"
			mkfs.ext4 -q $partboot
		fi

		# TODO : follow https://savannah.gnu.org/bugs/?55093 & remove --type luks1 when grub2 supports LUKS2 format
		echo "${GREEN}## encrypting $partroot${BLACK}"
		if [ $encrypted_boot = false ] ; then
			cryptsetup --batch-mode --force-password --verify-passphrase --cipher aes-xts-plain64 --key-size 512 --hash sha512 luksFormat $partroot
		else
			cryptsetup --batch-mode --force-password --verify-passphrase --cipher aes-xts-plain64 --key-size 512 --hash sha512 --type luks1 luksFormat $partroot		
		fi
	
		maproot="croot"

		echo "${GREEN}## opening $partroot${BLACK}"
		cryptsetup luksOpen $partroot $maproot
		echo "${GREEN}## mkfs /dev/mapper/$maproot${BLACK}"
		mkfs.ext4 /dev/mapper/$maproot
		mount /dev/mapper/$maproot $mountpoint

		if [ $luks_keyfile = true ] ; then
			echo "${GREEN}## adding luks keyfile to avoid multiple passwords on boot${BLACK}"
			dd bs=512 count=4 if=/dev/random of=/root/crypto_keyfile.bin iflag=fullblock
			cryptsetup -v luksAddKey $partroot /root/crypto_keyfile.bin
		fi
		
		if [ $encrypted_boot = false ] ; then
			mkdir -p $mountpoint/boot
			mount $partboot $mountpoint/boot
		fi
	else
		echo "${GREEN}## mkfs $partroot${BLACK}"
		mkfs.ext4 $partroot
		mount $partroot $mountpoint
	fi

	if [ $enable_uefi = true ] ; then
		echo "${GREEN}## mkfs $partesp${BLACK}"
		mkfs.vfat -F 32 $partesp

		mkdir -p $mountpoint/efi
		mount $partesp $mountpoint/efi
	fi
}

update_mirrorlist() {
	mirrorlist_url="https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4"

	mirrorlist_tmp=$(mktemp --suffix=-mirrorlist)
	curl -so ${mirrorlist_tmp} ${mirrorlist_url}

	if [[ -s ${mirrorlist_tmp} ]]; then
		shopt -s lastpipe
		tail -n +7  ${mirrorlist_tmp} | grep -oP "^## \K[a-zA-Z ]+" | sed 's/$/\n/g' | readarray countries
		selected_country=$(whiptail --nocancel --menu "select pacman mirrorlist country:" 22 60 14 "${countries[@]}" 3>&1 1>&2 2>&3)
		sed -i -n "/## $selected_country/,/^\$/p" ${mirrorlist_tmp}
		sed -i 's/^#Server/Server/g' ${mirrorlist_tmp}

		mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig &&
		mv ${mirrorlist_tmp} /etc/pacman.d/mirrorlist
		chmod +r /etc/pacman.d/mirrorlist
	else
		echo "${GREEN}## could not download mirrorlist${BLACK}"
		echo "Server=https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
	fi
}

check_multilib_required() {
	multilib_enabled=false
	if [[ `uname -m` == x86_64 ]] && [ $install_desktop != false ] ; then
		if [[ "${install_packages[@]}" =~ "steam" ]] || [[ "${install_packages[@]}" =~ "wine" ]] ; then
			echo "${GREEN}## enabling multilib repository${BLACK}"
			sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
			multilib_enabled=true
		fi
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

update_pacman_keys(){
    echo "${GREEN}## refreshing pacman keys${BLACK}"
    #pacman -Sy --noconfirm archlinux-keyring
    for server in ha.pool.sks-keyservers.net \
                hkps://keyserver.ubuntu.com:443 \
                hkp://keys.gnupg.net:80 \
                hkp://p80.pool.sks-keyservers.net:80 \
                keyserver.ubuntu.com \
                hkp://keyserver.ubuntu.com:80 \
                pgp.mit.edu; do
        pacman-key --refresh-keys --keyserver "$server" && break || echo "${GREEN}## Trying new keyserver...${BLACK}"
    done
}

install_base(){
	echo "${GREEN}## installing base system${BLACK}"
	pacstrap $mountpoint base $install_kernel linux-firmware

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq intel` ; then
		echo "${GREEN}## installing intel ucode${BLACK}"
		pacstrap $mountpoint intel-ucode
	fi

	if `cat /proc/cpuinfo | grep vendor_id | grep -iq amd` ; then
		echo "${GREEN}## installing amd ucode${BLACK}"
		pacstrap $mountpoint amd-ucode
	fi
}

configure_fstab(){
	echo "${GREEN}## generating fstab entries${BLACK}"
	genfstab -U -p $mountpoint >> $mountpoint/etc/fstab

	if [ $enable_trim = true ] ; then
		arch_chroot "systemctl enable fstrim.timer"
	fi
}

arch_chroot(){
	arch-chroot $mountpoint /bin/bash -c "${1}"
}

configure_system(){
	echo "${GREEN}## updating locale${BLACK}"
	sed -i -e "s/#$selected_locale/$selected_locale/" $mountpoint/etc/locale.gen
	arch_chroot "locale-gen"
	echo LANG=$selected_locale > $mountpoint/etc/locale.conf
	arch_chroot "export LANG=$selected_locale"

	if [ $enable_luks = true ] ; then
		echo "${GREEN}## adding encrypt hook${BLACK}"
		sed -i "/^HOOKS/s/filesystems/encrypt filesystems/" $mountpoint/etc/mkinitcpio.conf

		if [ $luks_keyfile = true ] ; then
			mv /root/crypto_keyfile.bin $mountpoint/crypto_keyfile.bin
			chmod 000 $mountpoint/crypto_keyfile.bin
			chmod 600 $mountpoint/boot/initramfs-linux*
			sed -i 's/^FILES=.*/FILES=(\/crypto_keyfile.bin)/' $mountpoint/etc/mkinitcpio.conf
		fi

		arch_chroot "mkinitcpio -p $install_kernel"
	fi

	echo "${GREEN}## writing vconsole.conf${BLACK}"
	echo "KEYMAP=$selected_keymap" > $mountpoint/etc/vconsole.conf
	echo "FONT=Lat2-Terminus16" >> $mountpoint/etc/vconsole.conf

	echo "${GREEN}## updating localtime${BLACK}"
	arch_chroot "ln -s /usr/share/zoneinfo/$selected_timezone /etc/localtime"
	arch_chroot "hwclock --systohc --utc"

	echo "${GREEN}## setting hostname${BLACK}"
	echo $hostname > $mountpoint/etc/hostname

	echo "${GREEN}## enabling haveged for better randomness${BLACK}"
	pacstrap $mountpoint haveged
	arch_chroot "systemctl enable haveged"

	echo "${GREEN}## disabling root login${BLACK}"
	arch_chroot "passwd --lock root"

	if [ $enable_swap = true ] ; then
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
}

install_bootloader()
{
	echo "${GREEN}## installing grub to ${DSK}${BLACK}"
	pacstrap $mountpoint grub os-prober

	if [ $enable_luks = true ] ; then
		cryptdevice="cryptdevice=$partroot:$maproot"

		if [ $enable_trim = true ] ; then 
			echo "${GREEN}## appending allow-discards for TRIM support${BLACK}"
			cryptdevice+=":allow-discards"
		fi

		#if [ $luks_keyfile = true ] ; then
		#	cryptdevice+=" cryptkey=rootfs:/crypto_keyfile.bin"
		#fi
		chmod -R g-rwx,o-rwx $mountpoint/boot 

		sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$#$cryptdevice\"#" $mountpoint/etc/default/grub
		sed -i -e "s/#GRUB_DISABLE_LINUX_UUID/GRUB_DISABLE_LINUX_UUID/" $mountpoint/etc/default/grub
		
		if [ $encrypted_boot = true ] ; then
			sed -i -e "s/#GRUB_ENABLE_CRYPTODISK/GRUB_ENABLE_CRYPTODISK/" $mountpoint/etc/default/grub
		fi
	fi

	echo -e "\nGRUB_DISABLE_SUBMENU=true" | tee --append $mountpoint/etc/default/grub

	sed -i -e "s/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/" $mountpoint/etc/default/grub
	sed -i -e "s/#GRUB_SAVEDEFAULT/GRUB_SAVEDEFAULT/" $mountpoint/etc/default/grub
	sed -i -e "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=10/" $mountpoint/etc/default/grub
	
	if [ $enable_uefi = true ] ; then
		pacstrap $mountpoint dosfstools efibootmgr
		arch_chroot "grub-install --efi-directory=/efi --target=x86_64-efi --bootloader-id=grub --recheck"
		#efibootmgr --create --disk ${DSK} --part 1 --loader /EFI/grub/grubx64.efi --label "Grub Boot Manager" --verbose
	else
		pacstrap $mountpoint memtest86+ 
		arch_chroot "grub-install --target=i386-pc --recheck ${DSK}"
	fi

	echo "${GREEN}## printing /etc/default/grub${BLACK}"
	cat $mountpoint/etc/default/grub

	echo "${GREEN}## generating /boot/grub/grub.cfg${BLACK}"
	arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

	cat <<-'EOF' | tee $mountpoint/boot/grub/custom.cfg
		menuentry "System shutdown" {
			echo "System shutting down..."
			halt
		}
		menuentry "System restart" {
			echo "System rebooting..."
			reboot
		}
		if [ ${grub_platform} == "efi" ]; then
			menuentry "Firmware setup" {
				fwsetup
			}
		fi
	EOF

	if [ $enable_luks = true ] ; then
		echo "${GREEN}## printing cryptdevice line from /boot/grub/grub.cfg${BLACK}"
		cat $mountpoint/boot/grub/grub.cfg | grep -m 1 "cryptdevice"
	fi
}

create_user() {
	echo "${GREEN}## adding user: $username${BLACK}"
	pacstrap $mountpoint sudo nano
	arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage,optical -s /bin/bash $username"

	echo "${GREEN}## setting password for user $username${BLACK}"
	arch_chroot "printf \"$userpass\n$userpass\" | passwd $username"

	echo "${GREEN}## allowing members of wheel group as sudoers${BLACK}"
	sed -i '/%wheel ALL=(ALL) ALL/s/^#//' $mountpoint/etc/sudoers

	echo "export EDITOR=\"nano\"" >> $mountpoint/home/$username/.bashrc
}

install_network_daemon() {
	enable_networkmanager=false
	if [ $setup_network == "networkmanager" ] ; then
			echo "${GREEN}## installing NetworkManager${BLACK}"
			pacstrap $mountpoint networkmanager
			arch_chroot "systemctl enable NetworkManager && systemctl enable NetworkManager-dispatcher.service"
			enable_networkmanager=true
	elif [ $setup_network == "networkd" ] ; then
			echo "${GREEN}## enabling systemd-networkd${BLACK}"
			arch_chroot "systemctl enable systemd-networkd.service"
			echo "${GREEN}## read https://wiki.archlinux.org/index.php/Systemd-networkd for configuration${BLACK}"
	fi
}

enable_ntpd() {
	echo "${GREEN}## enabling network time daemon${BLACK}"
	pacstrap $mountpoint ntp

	#if [ $enable_networkmanager = true ] ; then
		# TODO : now an aur package??
		#pacstrap $mountpoint networkmanager-dispatcher-ntpd
	#fi

	arch_chroot "ntpd -q"
	arch_chroot "systemctl enable ntpd.service"
}

enable_sshd() {
	pacstrap $mountpoint openssh
	arch_chroot "systemctl enable sshd.service"
}

paccache_cleanup() {
	echo "${GREEN}## adding weekly timer to cleanup pacman pkg cache${BLACK}"
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
	echo "${GREEN}## Installing yay AUR Helper${BLACK}"
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
	# TODO : concat all required pkgs and exec pacstrap once

	pacstrap $mountpoint xorg-server xorg-xinit pulseaudio 

	if [ $install_desktop == "mate" ] ; then
		pacstrap $mountpoint mate mate-extra network-manager-applet gnome-icon-theme mate-applet-dock
	elif [ $install_desktop == "gnome" ] ; then
		pacstrap $mountpoint gnome gnome-extra
	elif [ $install_desktop == "xfce" ] ; then
		pacstrap $mountpoint xfce4 xfce4-goodies
	elif [ $install_desktop == "kde" ] ; then
		pacstrap $mountpoint plasma plasma-wayland-session kde-graphics-meta kde-utilities-meta dolphin packagekit-qt5
	elif [ $install_desktop == "budgie-desktop" ] ; then
		pacstrap $mountpoint budgie-desktop budgie-extras gnome-control-center network-manager-applet gnome-themes-extra
		# gnome --ignore=gdm,epiphany,cheese,gnome-contacts,gnome-maps,gnome-music,gnome-shell,gnome-shell-extensions,yelp,vino
	fi

	if [ $install_driver == "virtualbox-guest-utils" ] ; then
		pacstrap $mountpoint virtualbox-guest-utils
	fi

	pacstrap $mountpoint mesa $install_driver

	if [ $multilib_enabled = true ] ; then
		pacstrap $mountpoint lib32-mesa
	fi

	if [ $install_driver == "xf86-video-intel" ] ; then
		pacstrap $mountpoint vulkan-icd-loader vulkan-intel intel-media-driver
	elif [ $install_driver == "xf86-video-amdgpu" ] ; then
		pacstrap $mountpoint vulkan-icd-loader vulkan-radeon libva-mesa-driver
		if [ $multilib_enabled = true ] ; then
			pacstrap $mountpoint lib32-libva-mesa-driver lib32-vulkan-radeon
		fi
	elif [ $install_driver == "xf86-video-ati" ] ; then
		pacstrap $mountpoint mesa-vdpau
		if [ $multilib_enabled = true ] ; then
			pacstrap $mountpoint lib32-mesa-vdpau
		fi
    elif [ $install_driver == "nvidia" ] ; then
        if [ $multilib_enabled = true ] ; then
			pacstrap $mountpoint lib32-nvidia-utils
		fi
		if [ $install_kernel != "linux" ] ; then
            pacstrap $mountpoint nvidia-dkms
		fi
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
		echo "${GREEN}## enabling autologin for user: $username${BLACK}"
		mkdir -p $mountpoint/etc/systemd/system/getty@tty1.service.d
		echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" \
			| tee $mountpoint/etc/systemd/system/getty@tty1.service.d/autologin.conf
		echo "${GREEN}## Enabling Xorg Autostart${BLACK}"
		echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> $mountpoint/home/$username/.bash_profile
		
		if [ $install_desktop == "mate" ] ; then
			echo "exec mate-session" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "gnome" ] ; then
			echo -e "export XDG_SESSION_TYPE=x11\nexport GDK_BACKEND=x11\nexec gnome-session" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "xfce" ] ; then
			echo "exec startxfce4" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "kde" ] ; then
			echo -e "export DESKTOP_SESSION=plasma\nexec startplasma-x11" > $mountpoint/home/$username/.xinitrc
		elif [ $install_desktop == "budgie-desktop" ] ; then
			echo -e "export XDG_CURRENT_DESKTOP=Budgie:GNOME\nexec budgie-desktop" > $mountpoint/home/$username/.xinitrc
		fi		
		arch_chroot "chown -R $username:users /home/$username"
	elif [ $install_login == "lightdm" ] ; then
		pacstrap $mountpoint lightdm lightdm-gtk-greeter
		arch_chroot "systemctl enable lightdm.service"
	elif [ $install_login == "gdm" ] ; then
		pacstrap $mountpoint gdm
		arch_chroot "systemctl enable gdm.service"
	elif [ $install_login == "sddm" ] ; then
		pacstrap $mountpoint sddm
		arch_chroot "systemctl enable sddm.service"
	fi

	echo "${GREEN}## Installing Fonts${BLACK}"
	pacstrap $mountpoint ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1

	if [ $multilib_enabled = true ] ; then
		sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' $mountpoint/etc/pacman.conf
	fi
}

install_firejail()
{
	pacstrap $mountpoint firejail apparmor

	sed -i -e "\#^GRUB_CMDLINE_LINUX_DEFAULT=#s#\"\$#apparmor=1 security=apparmor\"#" $mountpoint/etc/default/grub
	arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

	arch_chroot "systemctl enable apparmor.service"

	echo "apparmor" | tee $mountpoint/etc/firejail/globals.local

	cat <<-'EOF' | tee $mountpoint/etc/pacman.d/hooks/firejail.hook
		[Trigger]
		Type = File
		Operation = Install
		Operation = Upgrade
		Operation = Remove
		Target = usr/bin/*
		Target = usr/local/bin/*
		Target = usr/share/applications/*.desktop

		[Action]
		Description = Configure symlinks in /usr/local/bin based on firecfg.config...
		When = PostTransaction
		Depends = firejail
		Exec = /bin/sh -c 'firecfg &>/dev/null'
	EOF

	#arch_chroot "apparmor_parser -r /etc/apparmor.d/firejail-default"
	# aa-enforce firejail-default
	# TODO : as created user exec: firecfg --fix-sound && firecfg --fix
}

finish_setup() {
	#TODO: offer to umount | reboot | poweroff | do nothing
	if whiptail --yesno "Reboot now?" 8 40 ; then
		echo "${GREEN}## unmounting and rebooting${BLACK}"

		if [ $enable_uefi = true ] ; then
			umount -l $partesp
		fi
		umount -l $mountpoint

		if [ $enable_luks = true ] ; then
			cryptsetup luksClose $maproot
		fi

		reboot
	fi
}

function main() {
	check_net_connectivity
	set_variables
	update_mirrorlist
	check_multilib_required
	partition_disk
	format_disk
	update_pacman_keys
	install_base
	configure_fstab
	configure_system
	install_bootloader
	create_user
	install_network_daemon
	if [ $enable_ntpd = true ] ; then
		enable_ntpd
	fi
	if [ $enable_sshd = true ] ; then
		enable_sshd
	fi
	paccache_cleanup
	if [ $install_aur = true ] ; then
		install_aur_helper
	fi
	if [ $install_desktop != false ] ; then
		install_desktop_environment
	fi
	install_mirrorlist_reflector_hook
	if [ $enable_firejail = true ] ; then
		install_firejail
	fi
	finish_setup
}

main
