#!/bin/bash

#          /:-------------:\
#       :-------------------::
#     :-----------/shhOHbmp---:\
#   /-----------omMMMNNNMMD  ---:
#  :-----------sMMMMNMNMP.    ---:
# :-----------:MMMdP-------    ---\
#,------------:MMMd--------    ---:
#:------------:MMMd-------    .---:
#:----    oNMMMMMMMMMNho     .----:
#:--     .+shhhMMMmhhy++   .------/
#:-    -------:MMMd--------------:
#:-   --------/MMMd-------------;
#:-    ------/hMMMy------------:
#:-- :dMNdhhdNMMNo------------;
#:---:sdNMMMMNds:------------:
#:------:://:-------------::
#:---------------------://

BOOTTYPE=$1
time=$2
host=$3
pass=$4
user=$5
DISKNAME=$6
virtual=$(dmidecode -s system-product-name)
ROOTNAME=$7

#Set variables
if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then cpu="iucode-tool"; fi
if [[ $virtual = "KVM" ]]; then
   virtual="qemu-guest-agent"
else
   virtual=""
fi
if [[ $BOOTTYPE = "efi" ]]; then
   grub=""
else
   grub="grub2-pc"
fi

#Get DNF
if [[ $(df | grep /run/archiso/cowspace | wc -l) -gt 0 ]]; then mount -o remount,size=2G /run/archiso/cowspace; fi
wget -O - https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/33/Cloud/x86_64/images/$(curl -Ls https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/33/Cloud/x86_64/images/ | cut -d '"' -f 2 | grep raw.xz) | xzcat >fedora.img
DEVICE=$(losetup --show -fP fedora.img)
mkdir -p /loop
mount $(echo $DEVICE)p1 /loop
mkdir /media
cp -ax /loop /media
umount /loop
losetup -d $DEVICE
rm fedora.img

#Install the base system
mount -o bind /mnt /media/loop/mnt
sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
arch-chroot /media/loop dnf install -y --installroot=/mnt --releasever=33 --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck basesystem dnf glibc-langpack-en glibc-locale-source iputils NetworkManager
arch-chroot /mnt localedef -c -i en_US -f UTF-8 en_US-UTF-8

#Install packages
arch-chroot /mnt dnf install -y --setopt=install_weak_deps=False --setopt=keepcache=True kernel $grub passwd linux-firmware btrfs-progs dosfstools $cpu git $virtual cryptsetup-luks

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
printf "$pass\n$pass\n" | arch-chroot /mnt passwd

#Create user
arch-chroot /mnt useradd -m -s /bin/bash $user
printf "$pass\n$pass\n" | arch-chroot /mnt passwd $user

#Create encryption key
arch-chroot /mnt dd if=/dev/urandom of=/keyfile bs=32 count=1
arch-chroot /mnt chmod 600 /keyfile
echo "$pass" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /keyfile
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$ROOTNAME) none" > /mnt/etc/crypttab

#Create bootloader
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt bootctl install
   echo "default  fedora.conf" > /mnt/boot/loader/loader.conf
   echo "timeout  4" >> /mnt/boot/loader/loader.conf
   echo "editor   no" >> /mnt/boot/loader/loader.conf
   arch-chroot /mnt dnf reinstall -y kernel-core
   rm /mnt/boot/loader/entries/*
   rm /mnt/boot/loader/random-seed
   find /mnt/boot -name "linux" -exec mv -t /mnt/boot {} +
   find /mnt/boot -name "initrd" -exec mv -t /mnt/boot {} +
   find /mnt/boot -name "*x86_64" -exec rmdir -p {} + 2>/dev/null
   echo "title Fedora" > /mnt/boot/loader/entries/fedora.conf
   echo "linux /linux" >> /mnt/boot/loader/entries/fedora.conf
   echo "initrd   /initrd" >> /mnt/boot/loader/entries/fedora.conf
   echo "options  cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot root=dev/mapper/cryptroot rootflags=subvol=/_active/rootvol rw" >> /mnt/boot/loader/entries/fedora.conf
else
   arch-chroot /mnt grub2-install /dev/$DISKNAME
   arch-chroot /mnt grub2-mkconfig -o /boot/grub2/grub.cfg
fi

#Clean
umount /media/loop/mnt
rm -r /media/loop
