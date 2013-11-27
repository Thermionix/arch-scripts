#!/bin/bash

command -v whiptail >/dev/null 2>&1 || { echo "whiptail required for this script" >&2 ; exit 1 ; }

net_connectivity() {
	echo "## checking internet connectivity"
	ping -c 2 www.google.com
	#ip route add default via <gw-ip>
}

enable_ssh() {
	systemctl start sshd 
	echo "## set passwd for login with ssh root@hostname"
	passwd
	ip addr | grep "inet"
}

user_variables() {
	echo "## defining variables for installation"
	# cat /etc/locale.gen | grep -oP "^#\K[a-zA-Z0-9@._-]+"
	locale=$(whiptail --nocancel --inputbox "Set locale:" 10 40 "en_AU.UTF-8" 3>&1 1>&2 2>&3)
	keyboard=$(whiptail --nocancel --inputbox "Set keyboard:" 10 40 "us" 3>&1 1>&2 2>&3)
	zone=$(whiptail --nocancel --inputbox "Set zone:" 10 40 "Australia" 3>&1 1>&2 2>&3)
	subzone=$(whiptail --nocancel --inputbox "Set subzone:" 10 40 "Melbourne" 3>&1 1>&2 2>&3)
	country=$(whiptail --nocancel --inputbox "Set mirrorlist country code:" 10 40 "AU" 3>&1 1>&2 2>&3)
	hostname=$(whiptail --nocancel --inputbox "Set hostname:" 10 40 "arch-laptop" 3>&1 1>&2 2>&3)
	username=$(whiptail --nocancel --inputbox "Set username:" 10 40 "thermionix" 3>&1 1>&2 2>&3)
}

update_locale() {
	echo "## updating locale"
	loadkeys $keyboard
	export LANG=$locale
	sed -i -e "s/#$locale/$locale/" /etc/locale.gen
	locale-gen
}

partition_disk() {
	disks=`parted --list | awk -F ": |, |Disk | " '/Disk \// { print $2" "$3$4 }'`
	DSK=$(whiptail --nocancel --menu "Select the Disk to install to" 18 45 10 $disks 3>&1 1>&2 2>&3)

	HAS_TRIM=0
	if [ -n "$(hdparm -I ${DSK} 2>&1 | grep 'TRIM supported')" ]; then
		HAS_TRIM=1
	fi

	labelroot="luksroot"
	labelswap="luksswap"
	labelboot="boot"
	partroot="/dev/disk/by-partlabel/$labelroot"
	partswap="/dev/disk/by-partlabel/$labelswap"
	partboot="/dev/disk/by-partlabel/$labelboot"
	maproot="croot"
	mapswap="cswap"
	mountpoint="/mnt"

	swap_size=`awk '/MemTotal/ {printf( "%.0f\n", $2 / 1000 )}' /proc/meminfo`
	swap_size=$(whiptail --nocancel --inputbox "Set swap partition size \n(recommended based on meminfo):" 10 40 "$swap_size" 3>&1 1>&2 2>&3)
	boot_end=$(( 2 + 500 ))
	swap_end=$(( $boot_end + ${swap_size} ))

	echo "## creating partition bios_grub"
	parted -s ${DSK} mklabel gpt
	parted -s ${DSK} -a optimal unit MB mkpart primary 1 2
	parted -s ${DSK} set 1 bios_grub on
	echo "## creating partition $labelboot"
	parted -s ${DSK} -a optimal unit MB mkpart primary 2 $boot_end
	parted -s ${DSK} name 2 $labelboot
	echo "## creating partition $labelswap"
	parted -s ${DSK} -a optimal unit MB mkpart primary $boot_end $swap_end
	parted -s ${DSK} name 3 $labelswap
	echo "## creating partition $labelroot"
	parted -s ${DSK} -a optimal unit MB -- mkpart primary $swap_end -1
	parted -s ${DSK} name 4 $labelroot

	whiptail --title "generated partition layout" --msgbox "`parted -s ${DSK} print`" 20 70
}

encrypt_disk() {
	echo "## encrypting $partroot"
	cryptsetup -c aes-xts-plain64 -y -s 512 -h sha512 -r luksFormat $partroot
	echo "## opening $partroot"
	cryptsetup luksOpen $partroot $maproot
	echo "## mkfs /dev/mapper/$maproot"
	mkfs.ext4 /dev/mapper/$maproot
	echo "## mkfs $partboot"
	mkfs.ext4 $partboot
	echo "## mounting partitions"
	mount /dev/mapper/$maproot $mountpoint
	mkdir $mountpoint/boot
	mount $partboot $mountpoint/boot
}

update_mirrorlist() {
	echo "## attempting to download mirrorlist for country: ${country}"
	url="https://www.archlinux.org/mirrorlist/?country=${country}&use_mirror_status=on"
	tmpfile=$(mktemp --suffix=-mirrorlist)
	curl -so ${tmpfile} ${url}
	sed -i 's/^#Server/Server/g' ${tmpfile}
	if [[ -s ${tmpfile} ]]; then
		echo "## rotating the new list into place"
		mv -i /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig &&
		mv -i ${tmpfile} /etc/pacman.d/mirrorlist
	else
		echo "## could not download list, ranking original mirrorlist"
		cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
		sed '/^#\S/ s|#||' -i /etc/pacman.d/mirrorlist.backup
		rankmirrors --verbose -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist
	fi
	chmod +r /etc/pacman.d/mirrorlist
	nano /etc/pacman.d/mirrorlist
}

user_variables
update_locale
partition_disk
encrypt_disk
update_mirrorlist

echo "## installing base system"
pacstrap -i $mountpoint base base-devel openssh libnewt wget

echo "## generating fstab entries"
genfstab -U -p $mountpoint >> $mountpoint/etc/fstab
echo "$mapswap $partswap /dev/urandom swap,cipher=aes-xts-plain:sha256,size=256" >> $mountpoint/etc/crypttab
echo "/dev/mapper/$mapswap none swap defaults 0 0" >> $mountpoint/etc/fstab
if [ ${HAS_TRIM} -eq 1 ]; then
	echo "## adding trim support"
	sed -i -e 's/rw,/discard,rw,/' $mountpoint/etc/fstab
	sed -i -e 's/defaults/defaults,discard/' $mountpoint/etc/fstab
	sed -i -e 's/swap,/swap,discard,/' $mountpoint/etc/crypttab
fi
nano $mountpoint/etc/fstab
nano $mountpoint/etc/crypttab

arch_chroot() {
  arch-chroot $mountpoint /bin/bash -c "${1}"
}

echo "## updating locale"
sed -i -e "s/#$locale/$locale/" $mountpoint/etc/locale.gen
arch_chroot "locale-gen"
echo LANG=$locale > $mountpoint/etc/locale.conf
arch_chroot "export LANG=$locale"

echo "## adding encrypt hook"
sed -i -e "/^HOOKS/s/filesystems/encrypt filesystems/" $mountpoint/etc/mkinitcpio.conf
arch_chroot "mkinitcpio -p linux"

echo "## writing vconsole.conf"
echo "KEYMAP=$keyboard" > $mountpoint/etc/vconsole.conf
echo "FONT=Lat2-Terminus16" >> $mountpoint/etc/vconsole.conf

echo "## updating localtime"
arch_chroot "ln -s /usr/share/zoneinfo/$zone/$subzone /etc/localtime"
arch_chroot "hwclock --systohc --utc"

echo "## setting hostname"
echo $hostname > $mountpoint/etc/hostname

echo "## installing grub to ${DSK}"
pacstrap -i $mountpoint grub
arch_chroot "grub-install --recheck ${DSK}"
cryptdevice="cryptdevice=$partroot:$maproot"
if [ ${HAS_TRIM} -eq 1 ]; then
	echo "## appending allow-discards"
	cryptdevice+=":allow-discards"
fi
sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$#$cryptdevice\"#" $mountpoint/etc/default/grub
sed -i -e "s/#GRUB_DISABLE_LINUX_UUID/GRUB_DISABLE_LINUX_UUID/" $mountpoint/etc/default/grub 
nano $mountpoint/etc/default/grub
arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
whiptail --title "check cryptdevice in grub.cfg" --msgbox "`cat $mountpoint/boot/grub/grub.cfg | grep -m 1 "cryptdevice"`" 20 80

create_user() {
	echo "## adding user: $username"
	pacstrap -i $mountpoint sudo
	arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage -s /bin/bash $username"
	echo "## set password for user: $username"
	arch_chroot "passwd $username"
	sed -i '/%wheel ALL=(ALL) ALL/s/^#//' $mountpoint/etc/sudoers
}

enable_autologin() {
	if whiptail --yesno "enable autologin for user: $username?" 8 40 ; then
		echo "## enabling autologin for user: $username"
		mkdir $mountpoint/etc/systemd/system/getty@tty1.service.d
		pushd $mountpoint/etc/systemd/system/getty@tty1.service.d/
		echo "[Service]" > autologin.conf
		echo "ExecStart=" >> autologin.conf
		echo "ExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" >> autologin.conf
		popd
	fi
}

install_network_daemon() {
	case $(whiptail --menu "Choose a network daemon" 20 60 12 \
	"1" "dhcpcd" \
	"2" "NetworkManager" \
	3>&1 1>&2 2>&3) in
		1)
			echo "## enabling dhcpcd"
			arch_chroot "systemctl enable dhcpcd.service"
		;;
    		2)
			echo "## Installing NetworkManager"
			pacstrap -i $mountpoint networkmanager networkmanager-dispatcher-ntpd
			arch_chroot "systemctl enable NetworkManager"
		;;
	esac	
}

enable_ntpd() {
	if whiptail --yesno "enable network time?" 8 40 ; then
		echo "## enabling network time"
		pacstrap -i $mountpoint ntp
		arch_chroot "ntpd -q"
		arch_chroot "hwclock -w"
		arch_chroot "systemctl enable ntpd.service"
	fi
}

finish_setup() {
	if whiptail --yesno "Reboot now?" 8 40 ; then
		echo "## unmounting and rebooting"
		umount -l $mountpoint/boot
		umount -l $mountpoint
		cryptsetup luksClose $maproot
		reboot
	fi
}

create_user
enable_autologin
install_network_daemon
enable_ntpd
finish_setup
