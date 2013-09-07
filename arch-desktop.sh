#!/bin/bash
 
pacman -S xorg-server xorg-server-utils xorg-xinit mesa
 
pacman -S ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
 
pacman -S xf86-video-vesa
 
pacman -S mate mate-extras
echo "exec mate-session" > ~/.xinitrc
 
pacman -S firefox vlc p7zip clementine gstreamer0.10-plugins flashplugin
 
pacman -S openssh ntfsprogs rsync
 
pacman -S mumble steam
 
echo "complete -cf sudo" >> ~/.bashrc
 
#systemctl disable dhcpcd
#systemctl stop dhcpcd
#systemctl enable NetworkManager
#systemctl start NetworkManager
 
echo "## the next command will add startx after login to .bash_profile"
read -p "Press [Enter] key to continue"
test -f /home/$username/.bash_profile || cp /etc/skel/.bash_profile ~/.bash_profile
echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> ~/.bash_profile
