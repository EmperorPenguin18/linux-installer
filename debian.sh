#!/bin/bash

#       _,met$$$$$gg.
#    ,g$$$$$$$$$$$$$$$P.
#  ,g$$P"     """Y$$.".
# ,$$P'              `$$$.
#',$$P       ,ggs.     `$$b:
#`d$$'     ,$P"'   .    $$$
# $$P      d$'     ,    $$P
# $$:      $$.   -    ,d$$'
# $$;      Y$b._   _,d$P'
# Y$$.    `.`"Y$$$$P"'
# `$$b      "-.__
#  `Y$$
#   `Y$$.
#     `$$b.
#       `Y$$b.
#          `"Y$b._
#              `"""

BOOTTYPE=$1
time=$2
host=$3
rpass=$4
upass=$5
user=$6
DISKNAME=$7
UUID=$8

#Set variables
if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then
   cpu="iucode-tool intel"
else
   cpu="amd64"
fi
if [[ $BOOTTYPE = "efi" ]]; then
   grub=""
else
   grub="grub2"
fi

#Install base system to mounted disk
pacman -S debootstrap debian-archive-keyring --noconfirm
debootstrap --arch amd64 buster /mnt http://deb.debian.org/debian
sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
arch-chroot /mnt apt update && arch-chroot /mnt apt install -y gnupg locales

#Set locale
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Install packages
sed -e '/#/d' -i /mnt/etc/apt/sources.list && sed -e 's/main/main contrib non-free/' -i /mnt/etc/apt/sources.list
echo 'deb http://deb.xanmod.org releases main' | tee /mnt/etc/apt/sources.list.d/xanmod-kernel.list && wget -qO - https://dl.xanmod.org/gpg.key | arch-chroot /mnt apt-key add -
arch-chroot /mnt apt update
arch-chroot /mnt apt install -y linux-xanmod-edge firmware-linux $grub btrfs-progs dosfstools $(echo $cpu)-microcode network-manager git

#Clean up install
arch-chroot /mnt apt purge -y nano vim-common
arch-chroot /mnt apt upgrade -y
arch-chroot /mnt dpkg-reconfigure $(arch-chroot /mnt dpkg-query -l | grep linux-image | awk '{print $2}') $grub

#Set time
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

#Network stuff
echo $host > /mnt/etc/hostname
echo "127.0.0.1   localhost" > /mnt/etc/hosts
echo "::1   localhost" >> /mnt/etc/hosts
echo "127.0.1.1   $(echo $host).localdomain  $host" >> /mnt/etc/hosts
arch-chroot /mnt systemctl enable NetworkManager

#Create root password
printf "$rpass\n$rpass\n" | arch-chroot /mnt passwd

#Create user
arch-chroot /mnt useradd -m -s /bin/bash $user
printf "$upass\n$upass\n" | arch-chroot /mnt passwd $user

#Create bootloader
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt bootctl install
   echo "default  debian.conf" > /mnt/boot/loader/loader.conf
   echo "timeout  4" >> /mnt/boot/loader/loader.conf
   echo "editor   no" >> /mnt/boot/loader/loader.conf
   echo "title Debian" > /mnt/boot/loader/entries/debian.conf
   echo "linux /$(ls /mnt/boot | grep vmlinuz)" >> /mnt/boot/loader/entries/debian.conf
   echo "initrd   /$(ls /mnt/boot | grep .img)" >> /mnt/boot/loader/entries/debian.conf
   echo "options  root=UUID=\"$UUID\" rootflags=subvol=/_active/rootvol rw" >> /mnt/boot/loader/entries/debian.conf
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
   arch-chroot /mnt grub-mkconfig -o /boot/grub2/grub.cfg
fi
