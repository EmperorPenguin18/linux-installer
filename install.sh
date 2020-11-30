#!/bin/bash

#yay_install()
#{
#   pth=$(pwd)
#   pacman -S base-devel --needed --noconfirm
#   mkdir /home/build   chgrp nobody /home/build
#   chmod g+ws /home/build
#   setfacl -m u::rwx,g::rwx /home/build
#   setfacl -d --set u::rwx,g::rwx,o::- /home/build
#   usermod -d /home/build nobody
#   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
#   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/yay" >> /etc/sudoers
#   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
#   cd /home/build
#   sudo -u nobody git clone https://aur.archlinux.org/yay.git
#   chmod -R g+w yay/
#   cd yay
#   sudo -u nobody makepkg -si --noconfirm
#   cd ../
#   rm -r yay
#   cd $pth
#}

#Checks before starting
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi
if [ $(ls /usr/bin | grep pacman | wc -l) -lt 1 ]; then
   echo "This is not an Arch system"
   exit 1
fi
if ping -q -c 1 -W 1 google.com >/dev/null; then
  echo "The network is up"
else
  echo "The network is down"
  exit 1
fi

#Prepare for installation
clear
echo "-------------------------------------------------"
echo "           Welcome to linux-installer!           "
echo "-------------------------------------------------"
echo "Please answer the following questions to begin:"
echo
pacman -S dmidecode parted dosfstools util-linux reflector arch-install-scripts efibootmgr fzf wget --noconfirm --needed &>/dev/null
timedatectl set-ntp true
DISKNAME=$(lsblk | grep disk | awk '{print $1 " " $4;}' | fzf -i --prompt "Choose disk to install to. >" --layout reverse | awk '{print $1;}')
clear
read -p "Do you want hibernation enabled (Swap partition) [Y/n] " swap
distro=$(echo -e "Arch\nDebian\nFedora\nVoid" | fzf -i --prompt "What distro do you want to install? >" --layout reverse | awk '{print tolower($0)}')
clear
rm -rf /usr/share/zoneinfo/right
rm -rf /usr/share/zoneinfo/posix
time=$(find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | fzf -i --prompt "Choose a timezone. >" --layout reverse)
clear
read -p "What will the hostname of this computer be? >" host
read -s -p "Enter the root password. >" rpass
echo
read -s -p "Confirm root password. >" rpass_check
echo
if [ "${rpass}" != "${rpass_check}" ]; then echo "Passwords do not match"; exit 1; fi
read -p "Enter your username. >" user
read -s -p "Enter your user password. >" upass
echo
read -s -p "Confirm user password. >" upass_check
echo
if [ "${upass}" != "${upass_check}" ]; then echo "Passwords do not match"; exit 1; fi
read -p "This will delete all data on selected storage device. Are you sure you want to continue? [y/N] " sure
if [ "${sure}" != "y" ]; then exit 1; fi
clear

#Partition disk
#umount /mnt/boot
#umount /mnt
#sgdisk --zap-all /dev/$DISKNAME
#wipefs -a /dev/$DISKNAME
if [[ $(efibootmgr | wc -l) -gt 0 ]]; then
   BOOTTYPE="efi"
else
   BOOTTYPE="legacy"
   echo "Using legacy boot"
fi
DISKSIZE=$(lsblk --output SIZE -n -d /dev/$DISKNAME | sed 's/.$//')
MEMSIZE=$(dmidecode -t 17 | grep "Size.*MB" | awk '{s+=$2} END {print s / 1024}')
MEMSIZE=$(bc <<< "$MEMSIZE * 1.5")
if [ $(echo $DISKNAME | head -c 2 ) = "sd" ]; then
   DISKNAME2=$DISKNAME
else
   DISKNAME2=$(echo $DISKNAME)p
fi
if [[ $swap = "n" ]] && [[ $BOOTTYPE = "efi" ]]; then
   ROOTNAME=$(echo $DISKNAME2)2
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart esp fat32 1MB 261MB \
      set 1 esp on \
      mkpart root btrfs 261MB $(echo $DISKSIZE)GB
elif [[ $swap = "n" ]]; then
   ROOTNAME=$(echo $DISKNAME2)1
   parted --script /dev/$DISKNAME \
      mklabel msdos \
      mkpart primary btrfs 1MB $(echo $DISKSIZE)GB
      set 1 boot on
elif [[ $BOOTTYPE = "efi" ]]; then
   ROOTNAME=$(echo $DISKNAME2)2
   SWAPNAME=$(echo $DISKNAME2)3
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart esp fat32 1MB 261MB \
      set 1 esp on \
      mkpart root btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)GB \
      mkpart swap linux-swap $(expr $DISKSIZE - $MEMSIZE)GB $(echo $DISKSIZE)GB
else
   ROOTNAME=$(echo $DISKNAME2)1
   SWAPNAME=$(echo $DISKNAME2)2
   parted --script /dev/$DISKNAME \
      mklabel msdos \
      mkpart primary btrfs 1MB $(expr $DISKSIZE - $MEMSIZE)GB \
      set 1 boot on \
      mkpart primary linux-swap $(expr $DISKSIZE - $MEMSIZE)GB $(echo $DISKSIZE)GB
fi

#Format partitions
if [[ $BOOTTYPE = "efi" ]]; then
   #wipefs -a /dev/$(echo $DISKNAME2)1
   mkfs.fat -F 32 /dev/$(echo $DISKNAME2)1
fi
#wipefs -a /dev/$ROOTNAME
mkfs.btrfs /dev/$ROOTNAME
if [[ $swap != "n" ]]; then
   mkswap /dev/$SWAPNAME
   swapon /dev/$SWAPNAME
fi
mount /dev/$ROOTNAME /mnt

#BTRFS subvolumes
pth=$(pwd)
cd /mnt
btrfs subvolume create _active
btrfs subvolume create _active/rootvol
btrfs subvolume create _active/homevol
btrfs subvolume create _active/tmp
btrfs subvolume create _snapshots
cd $pth

#Mount subvolumes for install
umount /mnt
mount -o subvol=_active/rootvol /dev/$ROOTNAME /mnt
mkdir /mnt/{home,tmp,boot}
mount -o subvol=_active/tmp /dev/$ROOTNAME /mnt/tmp
if [[ $BOOTTYPE = "efi" ]]; then
   if [ "$distro" = "fedora" ] || [ "$distro" = "debian" ]; then
      mount /dev/$(echo $DISKNAME2)1 /mnt/boot
   else
      mkdir /mnt/boot/efi
      mount /dev/$(echo $DISKNAME2)1 /mnt/boot/efi
   fi
fi
mount -o subvol=_active/homevol /dev/$ROOTNAME /mnt/home

#Generate FSTAB
mkdir /mnt/etc
if [[ $BOOTTYPE = "efi" ]]; then
   if [ "$distro" = "fedora" ] || [ "$distro" = "debian" ]; then
      echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
   else
      echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot/efi   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
   fi
fi
UUID2=$(blkid -s UUID -o value /dev/$ROOTNAME)
if [[ $swap != "n" ]]; then echo UUID=$(blkid -s UUID -o value /dev/$SWAPNAME) none  swap  defaults 0  0 >> /mnt/etc/fstab; fi
if [[ $(lsblk -d -o name,rota | grep $DISKNAME | grep 1 | wc -l) -eq 1 ]]; then
   echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home/$(echo $user)/.snapshots btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
else
   echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home/$(echo $user)/.snapshots btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
fi

#Configure mirrors
reflector --country Canada --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Sy

#Install distro
virtual=$(dmidecode -s system-product-name)
chmod +x *.sh
if [[ $distro = "debian" ]]; then
   ./debian.sh $BOOTTYPE $time $host $rpass $upass $user $DISKNAME
elif [[ $distro = "fedora" ]]; then
   ./fedora.sh $BOOTTYPE $time $host $rpass $upass $user $DISKNAME $virtual
elif [[ $distro = "void" ]]; then
   ./void.sh $BOOTTYPE $time $host $rpass $upass $user $DISKNAME $virtual
else
   ./arch.sh $BOOTTYPE $time $host $rpass $upass $user $DISKNAME $virtual
fi
#*Distro*

echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"

#*Undo changes to host*
#*Encrypted disk*
