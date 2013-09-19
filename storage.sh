#!/bin/bash
 
#sudo echo "/dev/disk/by-label/storage /mnt/storage ext4 defaults 0 2" >> /etc/fstab
mkdir /mnt/storage
mount /mnt/storage
 
ln -s /mnt/storage/Downloads/ ~/Downloads
 
rm -rf ~/.local/share/Steam
ln -s /mnt/storage/steam/ ~/.local/share/Steam
 
rm -rf ~/.PlayOnLinux
ln -s /mnt/storage/games/PlayOnLinux ~/.PlayOnLinux
 
ln -s /mnt/storage/data/VirtualBox ~/.VirtualBox

ln -s /mnt/storage/games/winetricks/ ~/.cache/winetricks
ln -s /mnt/storage/games/.wine/ ~/.wine
 
pacman -S autofs
mkdir /media/fubox
#echo "/media/fubox /etc/autofs/auto.fubox --ghost" >> /etc/autofs/auto.master
#echo "music -fstype=cifs,ro,noperm ://192.168.1.62/share/music" > /etc/autofs/auto.fubox
systemctl enable autofs
