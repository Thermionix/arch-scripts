#!/bin/bash
 
CATALYST_CHECK=`grep "\[catalyst\]" /etc/pacman.conf`
if [ $? -ne 0 ]; then
echo -e '\n[catalyst]\nInclude = /etc/pacman.d/catalyst' | sudo tee --append /etc/pacman.conf
fi
 
echo -e "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch\nServer = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch\nServer = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | sudo tee /etc/pacman.d/catalyst
 
sudo pacman-key --keyserver pgp.mit.edu --recv-keys 0xabed422d653c3094
sudo pacman-key --lsign-key 0xabed422d653c3094
 
sudo pacman -Syy
 
sudo pacman -S base-devel linux-headers mesa-demos qt4
sudo pacman -S libtxc_dxtn lib32-libtxc_dxtn
 
sudo pacman -S catalyst-hook catalyst-utils
 
sudo sed -i -e "\#^GRUB_CMDLINE_LINUX=#s#\"\$# nomodeset\"#" /etc/default/grub
#sudo grub-mkconfig -o /boot/grub/grub.cfg
 
echo "blacklist radeon" | sudo tee /etc/modprobe.d/blacklist-radeon.conf
 
echo -e "blacklist snd_hda_intel\nblacklist snd_hda_codec_hdmi" | sudo tee /etc/modprobe.d/blacklist-hdmi.conf
 
sudo systemctl enable catalyst-hook
sudo systemctl start catalyst-hook
 
# sudo reboot
# sudo aticonfig --initial
# sudo aticonfig --initial=dual-head --screen-layout=right
# sudo aticonfig --tls=off
