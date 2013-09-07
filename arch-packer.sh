#!/bin/bash
 
sudo pacman -S --needed wget base-devel
echo "export EDITOR=\"nano\"" >> ~/.bashrc
 
mkdir packerbuild
pushd packerbuild
 
wget http://aur.archlinux.org/packages/pa/packer/packer.tar.gz
wget http://aur.archlinux.org/packages/pa/packer/PKGBUILD
 
makepkg -s PKGBUILD --install
 
popd
rm -rf packerbuild
 
#sudo packer -S npapi-vlc-git ttf-ms-fonts
