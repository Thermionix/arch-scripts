#!/bin/bash
 
if [[ `uname -m` == x86_64 ]]; then
  echo "## x86_64 detected, adding multilib repository"
  if [[ -z `grep -n "\[multilib\]" /etc/pacman.conf | cut -f1 -d:` ]]; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
  else
    sudo sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
  fi
fi
sudo pacman -Syy
 
#unset XMODIFIERS && export SDL_AUDIODRIVER=alsa && steam

pacman -S wine winetricks wine-mono wine_gecko
pacman -S alsa-lib alsa-plugins lib32-alsa-lib lib32-alsa-plugins lib32-mpg123 libpulse mpg123 lib32-libpulse lib32-openal
 
#winetricks videomemorysize=2048 3072?
WINEARCH=win32 winecfg
