arch-install.sh
============

Please read the ArchWiki [Installation Guide](https://wiki.archlinux.org/index.php/Installation_guide) and the [General 
Recomendations](https://wiki.archlinux.org/index.php/General_recommendations), also read the script.

For new improvements and bugs file an issue in GitHub or make a pull request.

Please test it in a VirtualBox virtual machine before running it on hardware.

### Installation

Internet connection is required, with wireless WIFI connection see [Wireless_network_configuration](https://wiki.archlinux.org/index.php/Wireless_network_configuration#Wi-Fi_Protected_Access) to bring up WIFI connection before starting installation

from a booted arch install iso;
```
curl -O https://raw.githubusercontent.com/Thermionix/arch-scripts/master/arch-install.sh
bash arch-install.sh
```
 
**Warning! This script deletes all partitions of the selected storage**

### Features

* UEFI or BIOS support
* Optional file swap (via systemd-swap)
* Periodic TRIM for SSD storage
* Intel/AMD processors microcode
* User creation and add to sudoers
* Common packages installation
* AUR utility installation (yay)
* Desktop environments (GDM, XFCE, Mate, KDE), display managers (GDM, SDDM, Lightdm) and no desktop environment
* Graphic drivers (intel, nvidia, amd)
* Optional _entire disk_ encryption with encrypted GRUB bootloader
* Hardened kernel available
* firejail & apparmor support

![Screenshot from 2020-09-06 11-41-24](https://user-images.githubusercontent.com/622615/92316407-0d6bba80-efe3-11ea-86c4-5ba04d289601.png)
![Screenshot from 2020-09-06 11-42-09](https://user-images.githubusercontent.com/622615/92316404-080e7000-efe3-11ea-98b7-6df7458b7c0c.png)
