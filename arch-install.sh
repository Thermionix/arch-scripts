#!/bin/bash

## enable ssh access:
# systemctl start sshd && passwd && ip addr
# ip route add default via <gw-ip>

echo "## defining variables for installation"
read -e -p "Set locale: " -i "en_AU.UTF-8" locale
read -e -p "Set keyboard: " -i "us" keyboard
read -e -p "Set zone: " -i "Australia" zone
read -e -p "Set subzone: " -i "Melbourne" subzone
read -e -p "Set mirrorlist country code: " -i "AU" country
read -e -p "Set hostname: " -i "arch-laptop" hostname
read -e -p "Set username: " -i "thermionix" username

echo "## updating locale"
loadkeys $keyboard
export LANG=$locale
sed -i -e "s/#$locale/$locale/" /etc/locale.gen
locale-gen

echo "## checking internet connectivity"
ping -c 2 www.google.com
read -p "Press [Enter] key to continue"

echo "## listing available disks"
parted --list | egrep "^Disk /"
read -e -p "Set disk to install to: " -i "sda" DSK

HAS_TRIM=0
if [ -n "$(hdparm -I /dev/${DSK} 2>&1 | grep 'TRIM supported')" ]; then
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
read -e -p "Set swap partition size (calculated from meminfo): " -i "$swap_size" swap_size
boot_end=$(( 2 + 500 ))
swap_end=$(( $boot_end + ${swap_size} ))

echo "## creating partition bios_grub"
parted -s /dev/${DSK} mklabel gpt
parted -s /dev/${DSK} -a optimal unit MB mkpart primary 1 2
parted -s /dev/${DSK} set 1 bios_grub on
echo "## creating partition $labelboot"
parted -s /dev/${DSK} -a optimal unit MB mkpart primary 2 $boot_end
parted -s /dev/${DSK} name 2 $labelboot
echo "## creating partition $labelswap"
parted -s /dev/${DSK} -a optimal unit MB mkpart primary $boot_end $swap_end
parted -s /dev/${DSK} name 3 $labelswap
echo "## creating partition $labelroot"
parted -s /dev/${DSK} -a optimal unit MB -- mkpart primary $swap_end -1
parted -s /dev/${DSK} name 4 $labelroot

echo "## /dev/${DSK} parition layout:"
parted -s /dev/${DSK} print
read -p "Press [Enter] key to continue"

echo "## running crypt benchmark"
cryptsetup benchmark
read -e -p "Set cipher: " -i "aes-xts-plain" cipher
read -e -p "Set keysize: " -i "512" keysize
echo "## encrypting $partroot"
cryptsetup -c $cipher -y -s $keysize -r luksFormat $partroot
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

echo "## installing base system"
pacstrap -i $mountpoint base base-devel

echo "## generating fstab entries"
genfstab -U -p $mountpoint >> $mountpoint/etc/fstab
echo "$mapswap $partswap /dev/urandom swap,cipher=aes-cbc-essiv:sha256,size=256" >> $mountpoint/etc/crypttab
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

echo "## installing grub to /dev/${DSK}"
pacstrap -i $mountpoint grub
arch_chroot "grub-install --recheck /dev/${DSK}"
cryptdevice="cryptdevice=$partroot:$maproot"
if [ ${HAS_TRIM} -eq 1 ]; then
  echo "## appending allow-discards"
  cryptdevice+=":allow-discards"
fi
sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$#$cryptdevice\"#" $mountpoint/etc/default/grub
sed -i -e "s/#GRUB_DISABLE_LINUX_UUID/GRUB_DISABLE_LINUX_UUID/" $mountpoint/etc/default/grub 
nano $mountpoint/etc/default/grub
arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
echo "## check cryptdevice in $mountpoint/boot/grub/grub.cfg"
cat $mountpoint/boot/grub/grub.cfg | grep -m 1 "cryptdevice"
read -p "Press [Enter] key to continue"

echo "## adding user: $username"
pacstrap -i $mountpoint sudo
arch_chroot "useradd -m -g users -G wheel,audio,network,power,storage -s /bin/bash $username"
echo "## set password for user: $username"
arch_chroot "passwd $username"
sed -i '/%wheel ALL=(ALL) ALL/s/^#//' $mountpoint/etc/sudoers
#echo "## disabling root login"
#arch_chroot "passwd -l root"

echo "## enabling autologin for user: $username"
mkdir $mountpoint/etc/systemd/system/getty@tty1.service.d
pushd $mountpoint/etc/systemd/system/getty@tty1.service.d/
echo "[Service]" > autologin.conf
echo "ExecStart=" >> autologin.conf
echo "ExecStart=-/usr/bin/agetty --autologin $username --noclear %I 38400 linux" >> autologin.conf
popd

echo "## enabling dhcpcd"
arch_chroot "systemctl enable dhcpcd.service"
## handle wifi?

echo "## enabling network time"
pacstrap -i $mountpoint ntp
arch_chroot "ntpd -q"
arch_chroot "hwclock -w"
arch_chroot "systemctl enable ntpd.service"

echo "## unmounting and rebooting"
read -p "Press [Enter] key to continue"
umount -l $mountpoint/boot
umount -l $mountpoint
cryptsetup luksClose $maproot
reboot
