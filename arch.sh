#!/bin/bash

#                   -`
#                  .o+`
#                 `ooo/
#                `+oooo:
#               `+oooooo:
#               -+oooooo+:
#             `/:-:++oooo+:
#            `/++++/+++++++:
#           `/++++++++++++++:
#          `/+++ooooooooooooo/`
#         ./ooosssso++osssssso+`
#        .oossssso-````/ossssss+`
#       -osssssso.      :ssssssso.
#      :osssssss/        osssso+++.
#     /ossssssss/        +ssssooo/-
#   `/ossssso+/:-        -:/+osssso+-
#  `+sso+:-`                 `.-/+oso:
# `++:.                           `-/+/
# .`                                 `/

BOOTTYPE=$1
time=$2
host=$3
rpass=$4
upass=$5
user=$6
DISKNAME=$7
virtual=$8

#Set variables
if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then
  cpu="iucode-tool intel"
else
  cpu="amd"
fi
if [[ $virtual = "VirtualBox" ]]; then
  virtual="virtualbox-guest-utils virtualbox-guest-dkms"
elif [[ $virtual = "KVM" ]]; then
  virtual="qemu-guest-agent"
else
  virtual=""
fi

#Install base system + packages
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-ucode opendoas networkmanager git $virtual

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Add btrfs to HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=()" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

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
echo "permit persist $user" > /mnt/etc/doas.conf

#Create bootloader
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
