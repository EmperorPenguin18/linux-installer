#!/bin/bash

set_locale()
{
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
   arch-chroot /mnt locale-gen
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
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

#Prompts
echo "-------------------------------------------------"
echo "           Welcome to linux-installer!           "
echo "-------------------------------------------------"
echo "Please answer the following questions to begin:"
echo
echo "Disks:"
lsblk | grep disk | awk '{print $1 " " $4;}'
echo
read -p "Choose what disk you want to install to. >" DISKNAME
read -p "Do you want hibernation enabled (Swap partition) [Y/n] " swap
read -p "What distro do you want to install? Default is Arch. [arch/debian/fedora/void] " distro
read -p "Choose a timezone (eg America/Toronto). >" time
read -p "What will the hostname of this computer be? >" host
read -s -p "Enter the root password. >" rpass
echo
read -p "Enter your username. >" user
read -s -p "Enter your user password. >" upass
echo

#Get host ready
pacman -S dmidecode parted btrfs-progs dosfstools util-linux reflector arch-install-scripts --noconfirm --needed
timedatectl set-ntp true

#Partition disk
DISKSIZE=$(lsblk --output SIZE -n -d /dev/$DISKNAME | sed 's/.$//')
MEMSIZE=$(dmidecode -t 17 | grep "Size.*MB" | awk '{s+=$2} END {print s / 1024}')
if [[ $swap = "n" ]]; then
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart P1 fat32 1MB 261MB \
      set 1 esp on \
      mkpart P2 btrfs 261MB $(echo $DISKSIZE)GB
else
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart P1 fat32 1MB 261MB \
      set 1 esp on \
      mkpart P2 btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)GB \
      mkpart P3 linux-swap $(expr $DISKSIZE - $MEMSIZE)GB $(echo $DISKSIZE)GB
fi
if [ $(echo $DISKNAME | head -c 2 ) = "sd" ]; then
   DISKNAME=$DISKNAME
else
   DISKNAME=$(echo $DISKNAME)p
fi

#Format partitions
mkfs.fat -F32 /dev/$(echo $DISKNAME)1
mkfs.btrfs /dev/$(echo $DISKNAME)2
if [[ $swap != "n" ]]; then
   mkswap /dev/$(echo $DISKNAME)3
   swapon /dev/$(echo $DISKNAME)3
fi
mount /dev/$(echo $DISKNAME)2 /mnt

#BTRFS subvolumes
path=$(pwd)
cd /mnt
btrfs subvolume create _active
btrfs subvolume create _active/rootvol
btrfs subvolume create _active/homevol
btrfs subvolume create _active/tmp
btrfs subvolume create _snapshots
cd $path

#Mount subvolumes for install
umount /mnt
mount -o subvol=_active/rootvol /dev/$(echo $DISKNAME)2 /mnt
mkdir /mnt/{home,tmp,boot}
mkdir /mnt/boot/EFI
mount -o subvol=_active/tmp /dev/$(echo $DISKNAME)2 /mnt/tmp
mount /dev/$(echo $DISKNAME)1 /mnt/boot/EFI
mount -o subvol=_active/homevol /dev/$(echo $DISKNAME)2 /mnt/home

#Generate FSTAB
mkdir /mnt/etc
UUID1=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)1)
UUID2=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)2)
echo UUID=$UUID1 /boot/EFI   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab
if [[ $swap != "n" ]]; then
   UUID3=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)3)
   echo UUID=$UUID3 none  swap  defaults 0  0 >> /mnt/etc/fstab
fi
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
if [[ $virtual = "VirtualBox" ]]; then
   virtual="virtualbox-guest-utils virtualbox-guest-dkms"
elif [[ $virtual = "KVM" ]]; then
   virtual="qemu-guest-agent"
else
   virtual=""
fi
if [[ $distro = "debian" ]]; then
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool intel"; else cpu="amd64"; fi
   pacman -S debootstrap --noconfirm
   debootstrap --no-check-gpg --arch amd64 buster /mnt http://deb.debian.org/debian
   echo "PATH=\"/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin\"" >> /etc/environment && source /etc/environment
   arch-chroot /mnt apt update && arch-chroot /mnt apt install -y gnupg locales
   set_locale
   echo 'deb http://deb.xanmod.org releases main' | tee /mnt/etc/apt/sources.list.d/xanmod-kernel.list && wget -qO - https://dl.xanmod.org/gpg.key | arch-chroot /mnt apt-key add -
   arch-chroot /mnt apt update
   echo "DEBIAN_FRONTEND=noninteractive apt -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" install linux-xanmod-edge firmware-linux efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-microcode network-manager git build-essential bison" > /mnt/apt.sh && arch-chroot /mnt chmod +x apt.sh && arch-chroot /mnt ./apt.sh && rm /mnt/apt.sh
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
   update-initramfs -k all -c
   arch-chroot /mnt apt install -y grub-efi-amd64
elif [[ $distro = "fedora" ]]; then
   chmod 777 ../
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
   cd ../
   su nobody -c "git clone https://aur.archlinux.org/dnf.git"
   cd dnf
   su nobody -c "makepkg -si --noconfirm"
   cd ../
   rm -r dnf
   cd linux-installer
   dnf install --installroot=/mnt --releasever=33 --setopt=install_weak_deps=False --setopt=keepcache=True --assumeyes --nodocs #systemd dnf glibc-langpack-en passwd rtkit policycoreutils NetworkManager audit firewalld selinux-policy-targeted kbd zchunk sudo vim-minimal systemd-udev rootfiles less iputils deltarpm sqlite lz4 xfsprogs
elif [[ $distro = "void" ]]; then
   chmod 777 ../
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
   cd ../
   su nobody -c "git clone https://aur.archlinux.org/xbps.git"
   cd xbps
   su nobody -c "makepkg -si --noconfirm"
   cd ../
   rm -r xpbs
   cd linux-installer
   XBPS_ARCH=x86_64 xbps-install -S -r /mnt -R "https://alpha.us.repo.voidlinux.org/" base-system
else
   if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool intel"; else cpu="amd"; fi
   pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-ucode opendoas networkmanager git $virtual
fi
#*Distro*

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
if [[ $distro != "debian" ]]; then set_locale; fi

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
arch-chroot /mnt systemctl enable NetworkManager

#Create root password
printf "$rpass\n$rpass\n" | arch-chroot /mnt passwd

#Create user
arch-chroot /mnt useradd -m $user
printf "$upass\n$upass\n" | arch-chroot /mnt passwd $user
echo "permit persist $user" > /mnt/etc/doas.conf

#Create bootloader
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=GRUB --recheck
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"

#*Undo changes to host*
#*Encrypted disk*
