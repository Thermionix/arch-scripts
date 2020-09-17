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

![Screenshot_20200906_151900](https://user-images.githubusercontent.com/622615/92319944-2a1ce800-f00d-11ea-8306-7e0305e1e6a1.png)
![Screenshot_20200906_151944](https://user-images.githubusercontent.com/622615/92319946-2b4e1500-f00d-11ea-9a3d-ce8839634026.png)
