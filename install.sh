#!/bin/bash

set_locale()
{
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
   arch-chroot /mnt locale-gen
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
}

yay_install()
{
   pth=$(pwd)
   pacman -S base-devel --needed --noconfirm
   mkdir /home/build
   chgrp nobody /home/build
   chmod g+ws /home/build
   setfacl -m u::rwx,g::rwx /home/build
   setfacl -d --set u::rwx,g::rwx,o::- /home/build
   usermod -d /home/build nobody
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/yay" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
   cd /home/build
   sudo -u nobody git clone https://aur.archlinux.org/yay.git
   chmod -R g+w yay/
   cd yay
   sudo -u nobody makepkg -si --noconfirm
   cd ../
   rm -r yay
   cd $pth
}

#Checks before starting
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi
if [ $(ls /usr/bin | grep pacman | wc -l) -lt 1 ]; then
   echo "This is not an Arch system"
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
DISKNAME=$(lsblk | grep disk | awk '{print $1 " " $4;}' | fzf --prompt "Choose disk to install to. >" --layout reverse | awk '{print $1;}')
clear
read -p "Do you want hibernation enabled (Swap partition) [Y/n] " swap
distro=$(echo -e "Arch\nDebian\nFedora\nVoid" | fzf --prompt "What distro do you want to install? >" --layout reverse | awk '{print tolower($0)}')
clear
rm -rf /usr/share/zoneinfo/right
rm -rf /usr/share/zoneinfo/posix
time=$(find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | fzf --prompt "Choose a timezone. >" --layout reverse)
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
clear

#Partition disk
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
if [[ $BOOTTYPE = "efi" ]]; then mkfs.fat -F32 /dev/$(echo $DISKNAME2)1; fi
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
   mkdir /mnt/boot/efi
   mount /dev/$(echo $DISKNAME2)1 /mnt/boot/efi
fi
mount -o subvol=_active/homevol /dev/$ROOTNAME /mnt/home

#Generate FSTAB
mkdir /mnt/etc
if [[ $BOOTTYPE = "efi" ]]; then echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot/efi   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab; fi
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

#Install packages
virtual=$(dmidecode -s system-product-name)
if [[ $distro = "debian" ]]; then
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool intel"; else cpu="amd64"; fi
   if [[ $BOOTTYPE = "efi" ]]; then grub="grub-efi-amd64"; else grub="grub2"; fi
   pacman -S debootstrap debian-archive-keyring --noconfirm
   debootstrap --arch amd64 buster /mnt http://deb.debian.org/debian
   sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
   arch-chroot /mnt apt update && arch-chroot /mnt apt install -y gnupg locales
   set_locale
   sed -e '/#/d' -i /mnt/etc/apt/sources.list && sed -e 's/main/main contrib non-free/' -i /mnt/etc/apt/sources.list
   echo 'deb http://deb.xanmod.org releases main' | tee /mnt/etc/apt/sources.list.d/xanmod-kernel.list && wget -qO - https://dl.xanmod.org/gpg.key | arch-chroot /mnt apt-key add -
   arch-chroot /mnt apt update
   arch-chroot /mnt apt install -y linux-xanmod-edge firmware-linux $grub efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-microcode network-manager git build-essential bison
   arch-chroot /mnt git clone https://github.com/Antynea/grub-btrfs
   arch-chroot /mnt make install -C grub-btrfs
   rm -r /mnt/grub-btrfs
   arch-chroot /mnt git clone https://github.com/Duncaen/OpenDoas
   arch-chroot /mnt OpenDoas/configure
   mv /mnt/config.* /mnt/OpenDoas/
   arch-chroot /mnt make -C OpenDoas
   arch-chroot /mnt make install -C OpenDoas
   rm -r /mnt/OpenDoas
   arch-chroot /mnt apt purge -y nano vim-common
   arch-chroot /mnt apt upgrade -y
   arch-chroot /mnt dpkg-reconfigure linux-xanmod-edge $grub
   #*efi*
   #*noninteractive*
   #*microcode?*
elif [[ $distro = "fedora" ]]; then
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool"; fi
   if [[ $virtual = "KVM" ]]; then virtual="qemu-guest-agent"; else virtual=""; fi
   if [[ $BOOTTYPE = "efi" ]]; then grub="grub2-efi-x64"; else grub="grub2-pc"; fi
   if [[ $(df | grep /run/archiso/cowspace | wc -l) -gt 0 ]]; then mount -o remount,size=2G /run/archiso/cowspace; fi
   wget -O - https://download.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/x86_64/images/$(curl -Ls https://download.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/x86_64/images/ | grep raw.xz | awk -F "\"" '{print $2}') | xzcat >fedora.img
   DEVICE=$(losetup --show -fP fedora.img)
   mkdir -p /loop
   mount $(echo $DEVICE)p1 /loop
   mkdir /media
   cp -ax /loop /media
   umount /loop
   losetup -d $DEVICE
   rm fedora.img
   mount -o bind /mnt /media/loop/mnt
   sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
   arch-chroot /media/loop dnf install -y --installroot=/mnt --releasever=33 --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck basesystem dnf glibc-langpack-en kernel linux-firmware $grub efibootmgr os-prober btrfs-progs dosfstools $cpu wpa_supplicant dhcpcd iputils NetworkManager git $virtual make automake gcc gcc-c++ kernel-devel bison #dhcpcd
   arch-chroot /mnt git clone https://github.com/Antynea/grub-btrfs
   arch-chroot /mnt make install -C grub-btrfs
   rm -r /mnt/grub-btrfs
   arch-chroot /mnt git clone https://github.com/Duncaen/OpenDoas
   arch-chroot /mnt OpenDoas/configure
   mv /mnt/config.* /mnt/OpenDoas/
   arch-chroot /mnt make -C OpenDoas
   arch-chroot /mnt make install -C OpenDoas
   rm -r /mnt/OpenDoas
   #*microcode?*
elif [[ $distro = "void" ]]; then
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool intel-ucode"; else cpu="linux-firmware-amd"; fi
   if [[ $virtual = "VirtualBox" ]]; then virtual="virtualbox-ose-guest virtualbox-ose-guest-dkms"; elif [[ $virtual = "KVM" ]]; then virtual="qemu-ga"; else virtual=""; fi
   if [[ $BOOTTYPE = "efi" ]]; then grub="grub-x86_64-efi"; else grub="grub"; fi
   wget https://alpha.us.repo.voidlinux.org/live/current/$(curl -s https://alpha.us.repo.voidlinux.org/live/current/ | grep void-x86_64-ROOTFS | cut -d '"' -f 2)
   tar xvf void-x86_64-ROOTFS-*.tar.xz -C /mnt
   echo "repository=https://alpha.us.repo.voidlinux.org/current" > /mnt/etc/xbps.d/xbps.conf
   echo "repository=https://alpha.us.repo.voidlinux.org/current/nonfree" >> /mnt/etc/xbps.d/xbps.conf
   echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib" >> /mnt/etc/xbps.d/xbps.conf
   echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib/nonfree" >> /mnt/etc/xbps.d/xbps.conf
   echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/xbps.conf
   arch-chroot /mnt ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default/
   arch-chroot /mnt dhcpcd
   arch-chroot /mnt xbps-install -Suy xbps
   arch-chroot /mnt xbps-install -uy
   arch-chroot /mnt xbps-install -y base-system
   arch-chroot /mnt xbps-remove -y base-voidstrap
   arch-chroot /mnt xbps-install -Sy linux-firmware $grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $cpu opendoas NetworkManager git $virtual
   arch-chroot /mnt xbps-reconfigure -fa
   #*microcode?*
else
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool intel"; else cpu="amd"; fi
   if [[ $virtual = "VirtualBox" ]]; then virtual="virtualbox-guest-utils virtualbox-guest-dkms"; elif [[ $virtual = "KVM" ]]; then virtual="qemu-guest-agent"; else virtual=""; fi
   pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-ucode opendoas networkmanager git $virtual
fi
#*Distro*

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
if [[ $distro == "fedora" ]] || [[ $distro == "arch" ]]; then set_locale; fi
if [[ $distro == "void" ]]; then
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/default/libc-locales
   arch-chroot /mnt xbps-reconfigure -f glibc-locales
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
fi

#Add btrfs to HOOKS
if [[ $distro = "arch" ]]; then
   echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
   echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
   echo "FILES=()" >> /mnt/etc/mkinitcpio.conf
   echo "HOOKS=(base udev autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
   arch-chroot /mnt mkinitcpio -P
fi

#Network stuff
echo $host > /mnt/etc/hostname
echo "127.0.0.1   localhost" > /mnt/etc/hosts
echo "::1   localhost" >> /mnt/etc/hosts
echo "127.0.1.1   $(echo $host).localdomain  $host" >> /mnt/etc/hosts
if [[ $distro != "void" ]]; then
   arch-chroot /mnt systemctl enable NetworkManager
else
   arch-chroot /mnt ln -s /etc/sv/NetworkManager /var/service/
fi

#Create root password
printf "$rpass\n$rpass\n" | arch-chroot /mnt passwd

#Create user
arch-chroot /mnt useradd -m -s /bin/bash $user
printf "$upass\n$upass\n" | arch-chroot /mnt passwd $user
echo "permit persist $user" > /mnt/etc/doas.conf

#Create bootloader
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"

#*Undo changes to host*
#*Encrypted disk*
