#!/bin/bash
 
sudo pacman -S xorg-server xorg-server-utils xorg-xinit mesa
 
sudo pacman -S ttf-droid ttf-liberation ttf-dejavu xorg-fonts-type1
sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
 
#pacman -S xf86-video-vesa
 
#pacman -S mate mate-extras
#echo "exec mate-session" > ~/.xinitrc
 
sudo pacman -S firefox vlc p7zip unrar zip clementine gstreamer0.10-plugins flashplugin
 
sudo pacman -S openssh ntfsprogs rsync
 
sudo pacman -S mumble steam

if [ `grep "complete -cf sudo" ~/.bashrc` -ne 0 ]; then 
  echo "complete -cf sudo" >> ~/.bashrc
fi
 
#systemctl disable dhcpcd
#systemctl stop dhcpcd
#systemctl enable NetworkManager
#systemctl start NetworkManager


if [ `grep "exec startx" ~/.bash_profile` -ne 0 ]; then 
  echo "## the next command will add startx after login to .bash_profile"
  read -p "Press [Enter] key to continue"
  test -f /home/$username/.bash_profile || cp /etc/skel/.bash_profile ~/.bash_profile
  echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx" >> ~/.bash_profile
fi
