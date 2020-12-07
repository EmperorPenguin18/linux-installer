#!/bin/bash

timedatectl set-ntp true
clear

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
echo "-------------------------------------------------"
echo "           Welcome to linux-installer!           "
echo "-------------------------------------------------"
echo "Please answer the following questions to begin:"
echo
pacman -Q | awk '{print $1}' > pre.txt
pacman -S dmidecode parted dosfstools util-linux reflector arch-install-scripts efibootmgr fzf wget cryptsetup --noconfirm --needed &>/dev/null
DISKNAME=$(lsblk | grep disk | awk '{print $1 " " $4;}' | fzf -i --prompt "Choose disk to install to. >" --layout reverse | awk '{print $1;}')
clear
read -p "Do you want hibernation enabled (Swap partition) [Y/n] " swap
distro=$(echo -e "Arch\nDebian\nFedora\nVoid" | fzf -i --prompt "What distro do you want to install? >" --layout reverse | awk '{print tolower($0)}')
clear
mv /usr/share/zoneinfo/right /usr/share/right
mv /usr/share/zoneinfo/posix /usr/share/posix
time=$(find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | fzf -i --prompt "Choose a timezone. >" --layout reverse)
clear
read -p "What will the hostname of this computer be? >" host
read -p "Enter your username. >" user
read -s -p "Enter your password. >" pass
echo
read -s -p "Confirm password. >" pass_check
echo
if [ "${pass}" != "${pass_check}" ]; then echo "Passwords do not match"; exit 1; fi
read -p "This will delete all data on selected storage device. Are you sure you want to continue? [y/N] " sure
if [ "${sure}" != "y" ]; then exit 1; fi
clear

#Partition disk
echo "Wiping all data on disk..."
dd if=/dev/zero of=/dev/$DISKNAME bs=4096 status=progress
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

#Encrypt stuff
echo "$pass" | cryptsetup -q luksFormat --type luks1 /dev/$ROOTNAME
echo "$pass" | cryptsetup open /dev/$ROOTNAME cryptroot
ENCRYPTNAME=mapper/cryptroot

#Format partitions
if [[ $BOOTTYPE = "efi" ]]; then
   mkfs.fat -F 32 /dev/$(echo $DISKNAME2)1
fi
mkfs.btrfs /dev/$ENCRYPTNAME
if [[ $swap != "n" ]]; then
   mkswap /dev/$SWAPNAME
   swapon /dev/$SWAPNAME
fi
mount /dev/$ENCRYPTNAME /mnt

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
mount -o subvol=_active/rootvol /dev/$ENCRYPTNAME /mnt
mkdir /mnt/{home,tmp,boot}
mount -o subvol=_active/tmp /dev/$ENCRYPTNAME /mnt/tmp
if [[ $BOOTTYPE = "efi" ]]; then
   if [ "$distro" = "fedora" ] || [ "$distro" = "debian" ]; then
      mount /dev/$(echo $DISKNAME2)1 /mnt/boot
   else
      mkdir /mnt/boot/efi
      mount /dev/$(echo $DISKNAME2)1 /mnt/boot/efi
   fi
fi
mount -o subvol=_active/homevol /dev/$ENCRYPTNAME /mnt/home

#Generate FSTAB
mkdir /mnt/etc
if [[ $BOOTTYPE = "efi" ]]; then
   if [ "$distro" = "fedora" ] || [ "$distro" = "debian" ]; then
      echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
   else
      echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot/efi   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
   fi
fi
UUID2=$(blkid -s UUID -o value /dev/$ENCRYPTNAME)
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
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
reflector --country Canada --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Sy

#Install distro
wget https://raw.githubusercontent.com/EmperorPenguin18/linux-installer/main/$(echo $distro).sh && chmod +x $(echo $distro).sh
if [[ $distro = "debian" ]]; then
   ./debian.sh $BOOTTYPE $time $host $pass $user $DISKNAME $ROOTNAME
elif [[ $distro = "fedora" ]]; then
   ./fedora.sh $BOOTTYPE $time $host $pass $user $DISKNAME $ROOTNAME
elif [[ $distro = "void" ]]; then
   ./void.sh $BOOTTYPE $time $host $pass $user $DISKNAME $ROOTNAME
else
   ./arch.sh $BOOTTYPE $time $host $pass $user $DISKNAME $ROOTNAME
fi

#Clean up
pacman -Q | awk '{print $1}' > post.txt
pacman -R $(diff pre.txt post.txt | grep ">" | awk '{print $2}') --noconfirm &>/dev/null
rm pre.txt post.txt
mv /usr/share/right /usr/share/zoneinfo/right
mv /usr/share/posix /usr/share/zoneinfo/posix
if [[ $BOOTTYPE = "efi" ]]; then
   if [ "$distro" = "fedora" ] || [ "$distro" = "debian" ]; then
      umount /mnt/boot
   else
      umount /mnt/boot/efi
   fi
fi
umount -A /dev/$ENCRYPTNAME
rm /etc/pacman.d/mirrorlist
mv /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
rm $(echo $distro).sh

echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"
