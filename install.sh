#!/bin/bash

pre_checks ()
{
   timedatectl set-ntp true
   clear
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
}

prepare_installation ()
{
   pacman -Q | awk '{print $1}' > pre.txt
   pacman -S dmidecode parted dosfstools util-linux reflector arch-install-scripts efibootmgr fzf wget cryptsetup bc --noconfirm --needed &>/dev/null
   DISKNAME=$(lsblk | awk '/disk/ {print $1 " " $4}' | fzf -i --prompt "Choose disk to install to. >" --layout reverse | awk '{print $1;}')
   clear
   read -p "Do you want hibernation enabled (Swap partition) [Y/n] " SWAP
   DISTRO=$(echo -e "Arch\nDebian\nFedora\nVoid" | fzf -i --prompt "What distro do you want to install? >" --layout reverse | awk '{print tolower($0)}')
   clear
   mv /usr/share/zoneinfo/right /usr/share/right
   mv /usr/share/zoneinfo/posix /usr/share/posix
   TIME=$(find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | fzf -i --prompt "Choose a timezone. >" --layout reverse)
   clear
   read -p "What will the hostname of this computer be? >" HOST
   read -p "Enter your username. >" USER
   read -s -p "Enter your password. >" PASS
   echo
   read -s -p "Confirm password. >" PASSCHECK
   echo
   if [ "${PASS}" != "${PASSCHECK}" ]; then echo "Passwords do not match"; exit 1; fi
   read -p "This will delete all data on selected storage device. Are you sure you want to continue? [y/N] " SURE
   if [ "${SURE}" != "y" ]; then exit 1; fi
   clear
}

setup_partitions ()
{
   echo "-------------------------------------------------"
   echo "                Partitioning disk                "
   echo "-------------------------------------------------"
   echo "Wiping all data on disk..."
   dd if=/dev/zero of=/dev/$DISKNAME bs=4096 status=progress
   if [[ $(efibootmgr | wc -l) -gt 0 ]]; then
      BOOTTYPE="efi"
   else
      BOOTTYPE="legacy"
      echo "Using legacy boot"
   fi
   DISKSIZE=$(lsblk --output SIZE -n -d -b /dev/$DISKNAME)
   DISKSIZE=$(bc <<< "$DISKSIZE / 1024 / 1024")
   MEMSIZE=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
   MEMSIZE=$(bc <<< "$MEMSIZE * 1.5 / 1024")
   if [ $(echo $DISKNAME | head -c 2 ) = "sd" ]; then
      DISKNAME2=$DISKNAME
   else
      DISKNAME2=$(echo $DISKNAME)p
   fi
}

partition_drive ()
{
   if [[ $SWAP = "n" ]] && [[ $BOOTTYPE = "efi" ]]; then
      parted --script /dev/$DISKNAME \
         mklabel gpt \
         mkpart esp fat32 1MB 261MB \
         set 1 esp on \
         mkpart root btrfs 261MB $(echo $DISKSIZE)MB
   elif [[ $SWAP = "n" ]]; then
      parted --script /dev/$DISKNAME \
         mklabel msdos \
         mkpart primary fat32 1MB 261MB \
         set 1 boot on \
         mkpart primary btrfs 261MB $(echo $DISKSIZE)MB
   elif [[ $BOOTTYPE = "efi" ]]; then
      parted --script /dev/$DISKNAME \
         mklabel gpt \
         mkpart esp fat32 1MB 261MB \
         set 1 esp on \
         mkpart root btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)MB \
         mkpart swap linux-swap $(expr $DISKSIZE - $MEMSIZE)MB $(echo $DISKSIZE)MB
   else
      parted --script /dev/$DISKNAME \
         mklabel msdos \
         mkpart primary fat32 1MB 261MB \
         set 1 boot on \
         mkpart primary btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)MB \
         mkpart primary linux-swap $(expr $DISKSIZE - $MEMSIZE)MB $(echo $DISKSIZE)MB
   fi
}

encrypt_partitions ()
{
   echo "$PASS" | cryptsetup -q luksFormat --type luks1 /dev/$(echo $DISKNAME2)2
   echo "$PASS" | cryptsetup open /dev/$(echo $DISKNAME2)2 cryptroot
}

format_partitions ()
{
   echo "-------------------------------------------------"
   echo "              Formatting partitions              "
   echo "-------------------------------------------------"
   mkfs.fat -F 32 /dev/$(echo $DISKNAME2)1
   mkfs.btrfs /dev/mapper/cryptroot
   if [[ $SWAP != "n" ]]; then
      mkswap /dev/$(echo $DISKNAME2)3
      swapon /dev/$(echo $DISKNAME2)3
   fi
   mount /dev/mapper/cryptroot /mnt
}

mount_subvolumes ()
{
   pth=$(pwd)
   cd /mnt
   btrfs subvolume create _active
   btrfs subvolume create _active/rootvol
   btrfs subvolume create _active/homevol
   btrfs subvolume create _active/tmp
   btrfs subvolume create _snapshots
   cd $pth
   umount /mnt
   mount -o subvol=_active/rootvol /dev/mapper/cryptroot /mnt
   mkdir /mnt/{home,tmp,boot}
   mount -o subvol=_active/tmp /dev/mapper/cryptroot /mnt/tmp
   mount /dev/$(echo $DISKNAME2)1 /mnt/boot
   mount -o subvol=_active/homevol /dev/mapper/cryptroot /mnt/home
}

generate_fstab ()
{
   mkdir /mnt/etc
   echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
   UUID2=$(blkid -s UUID -o value /dev/mapper/cryptroot)
   if [[ $SWAP != "n" ]]; then echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)3) none  swap  defaults 0  0 >> /mnt/etc/fstab; fi
   if [[ $(lsblk -d -o name,rota | grep $DISKNAME | grep 1 | wc -l) -eq 1 ]]; then
      echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home/$(echo $USER)/.snapshots btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
   else
      echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home/$(echo $USER)/.snapshots btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
   fi
}

configure_mirrors ()
{
   echo "-------------------------------------------------"
   echo "                Installing distro                "
   echo "-------------------------------------------------"
   cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
   reflector --country $(curl -sL https://raw.github.com/eggert/tz/master/zone1970.tab | grep $TIME | awk '{print $1}') --protocol https --sort rate --save /etc/pacman.d/mirrorlist
   pacman -Sy
}

install_distro ()
{
   wget https://raw.github.com/EmperorPenguin18/linux-installer/main/$(echo $DISTRO).sh && chmod +x $(echo $DISTRO).sh
   if [[ $DISTRO = "debian" ]]; then
      ./debian.sh $BOOTTYPE $PASS $USER $DISKNAME $(echo $DISKNAME2)2
   elif [[ $DISTRO = "fedora" ]]; then
      ./fedora.sh $BOOTTYPE $PASS $USER $DISKNAME $(echo $DISKNAME2)2
   elif [[ $DISTRO = "void" ]]; then
      ./void.sh $BOOTTYPE $PASS $USER $DISKNAME $(echo $DISKNAME2)2
   else
      ./arch.sh $BOOTTYPE $PASS $USER $DISKNAME $(echo $DISKNAME2)2
   fi
}

set_time ()
{
   echo "-------------------------------------------------"
   echo "                  Finishing up                   "
   echo "-------------------------------------------------"
   ln -sf /mnt/usr/share/zoneinfo/$(echo $TIME) /mnt/etc/localtime
   arch-chroot /mnt hwclock --systohc
}

set_hostname ()
{
   echo $HOST > /mnt/etc/hostname
   echo "127.0.0.1   localhost" > /mnt/etc/hosts
   echo "::1   localhost" >> /mnt/etc/hosts
   echo "127.0.1.1   $(echo $HOST).localdomain  $HOST" >> /mnt/etc/hosts
}

set_password ()
{
   printf "$PASS\n$PASS\n" | arch-chroot /mnt passwd
   printf "$PASS\n$PASS\n" | arch-chroot /mnt passwd $USER
}

clean_up ()
{
   pacman -Q | awk '{print $1}' > post.txt
   pacman -R $(diff pre.txt post.txt | grep ">" | awk '{print $2}') --noconfirm &>/dev/null
   rm pre.txt post.txt
   mv /usr/share/right /usr/share/zoneinfo/right
   mv /usr/share/posix /usr/share/zoneinfo/posix
   umount /mnt/boot
   umount -A /dev/mapper/cryptroot
   rm /etc/pacman.d/mirrorlist
   mv /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
}

pre_checks
echo "-------------------------------------------------"
echo "           Welcome to linux-installer!           "
echo "-------------------------------------------------"
echo "Please answer the following questions to begin:"
echo
prepare_installation
setup_partitions
partition_drive
encrypt_partitions
format_partitions
mount_subvolumes
generate_fstab
configure_mirrors
install_distro
set_time
set_hostname
set_password
clean_up
echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"
