#!/bin/bash
 
sudo pacman -S gnome gnome-flashback-session gnome-applets
sudo pacman -S gedit gnome-tweak-tool nautilus-open-terminal file-roller
# remove empathy epiphany
#echo "exec gnome-session --session=gnome-classic" > ~/.xinitrc
echo "exec gnome-session --session=gnome-flashback" > ~/.xinitrc
 
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.preferences sort-directories-first 'true'
gsettings set org.gtk.Settings.FileChooser show-hidden 'true'
gsettings set org.gnome.desktop.background show-desktop-icons 'true'
 
#gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \"['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']\"
#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name \"terminal\"
#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command \"gnome-terminal\"
#gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding \"\<Ctrl\>\<Alt\>t\"
