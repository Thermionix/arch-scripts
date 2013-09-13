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
 
sudo pacman -S lib32-alsa-lib wine winetricks wine-mono wine_gecko
 
#winetricks videomemorysize=2048 3072?
WINEARCH=win32 winecfg
