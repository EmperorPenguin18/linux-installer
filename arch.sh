#!/bin/bash

LCYAN='\033[1;36m'
printf "${LCYAN}                   -`\n"
printf "${LCYAN}                  .o+`\n"
printf "${LCYAN}                 `ooo/\n"
printf "${LCYAN}                `+oooo:\n"
printf "${LCYAN}               `+oooooo:\n"
printf "${LCYAN}               -+oooooo+:\n"
printf "${LCYAN}             `/:-:++oooo+:\n"
printf "${LCYAN}            `/++++/+++++++:\n"
printf "${LCYAN}           `/++++++++++++++:\n"
printf "${LCYAN}          `/+++ooooooooooooo/`\n"
printf "${LCYAN}         ./ooosssso++osssssso+`\n"
printf "${LCYAN}        .oossssso-````/ossssss+`\n"
printf "${LCYAN}       -osssssso.      :ssssssso.\n"
printf "${LCYAN}      :osssssss/        osssso+++.\n"
printf "${LCYAN}     /ossssssss/        +ssssooo/-\n"
printf "${LCYAN}   `/ossssso+/:-        -:/+osssso+-\n"
printf "${LCYAN}  `+sso+:-`                 `.-/+oso:\n"
printf "${LCYAN} `++:.                           `-/+/\n"
printf "${LCYAN} .`                                 `/\n"

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
VIRTUAL=$(dmidecode -s system-product-name)
ROOTNAME=$5

#Set variables
if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then
  CPU="iucode-tool intel"
else
  CPU="amd"
fi
if [[ $VIRTUAL = "VirtualBox" ]]; then
  VIRTUAL="virtualbox-guest-utils virtualbox-guest-dkms"
elif [[ $VIRTUAL = "KVM" ]]; then
  VIRTUAL="qemu-guest-agent"
else
  VIRTUAL=""
fi

#Install base system + packages
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $CPU)-ucode opendoas networkmanager git $VIRTUAL

#Set localization stuff
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Create encryption key
arch-chroot /mnt dd bs=512 count=4 if=/dev/random of=/crypto_keyfile.bin iflag=fullblock
arch-chroot /mnt chmod 600 /crypto_keyfile.bin
arch-chroot /mnt chmod 600 /boot/$(ls /mnt/boot | grep initramfs-linux)
echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /crypto_keyfile.bin

#Setup initramfs HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=(/crypto_keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev encrypt autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

#Network stuff
arch-chroot /mnt systemctl enable NetworkManager

#Create user
arch-chroot /mnt useradd -m -s /bin/bash $USER

#Configure doas
echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf
echo "permit persist $USER" >> /mnt/etc/doas.conf
arch-chroot /mnt su sebastien -c "git clone https://aur.archlinux.org/opendoas-sudo.git"
mv /mnt/opendoas-sudo/* /mnt
arch-chroot /mnt su sebastien -c "makepkg --noconfirm"
arch-chroot /mnt pacman -U opendoas*
rm -r /mnt/PKGBUILD /mnt/pkg /mnt/src /mnt/opendoas*
arch-chroot /mnt ln -s /etc/doas.conf /etc/sudoers

#Create bootloader
sed -i 's/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' /mnt/etc/default/grub
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot\"/g" /mnt/etc/default/grub
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
