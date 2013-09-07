#!/bin/bash
 
packer -S grub-holdshift
 
if [[ -z `grep -n "GRUB_FORCE_HIDDEN_MENU" /etc/default/grub | cut -f1 -d:` ]]; then
echo -e "\nGRUB_FORCE_HIDDEN_MENU=\"true\"" | sudo tee --append /etc/default/grub
fi
 
sudo grub-mkconfig -o /boot/grub/grub.cfg
