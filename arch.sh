#!/bin/sh

check_error ()
{
   if [ $? -ne 0 ]; then
      echo $1
      exit -1
   fi
}

LCYAN='\033[1;36m'
NC='\033[0m'
printf "${LCYAN}                   -\`\n"
printf "${LCYAN}                  .o+\`\n"
printf "${LCYAN}                 \`ooo/\n"
printf "${LCYAN}                \`+oooo:\n"
printf "${LCYAN}               \`+oooooo:\n"
printf "${LCYAN}               -+oooooo+:\n"
printf "${LCYAN}             \`/:-:++oooo+:\n"
printf "${LCYAN}            \`/++++/+++++++:\n"
printf "${LCYAN}           \`/++++++++++++++:\n"
printf "${LCYAN}          \`/+++ooooooooooooo/\`\n"
printf "${LCYAN}         ./ooosssso++osssssso+\`\n"
printf "${LCYAN}        .oossssso-\`\`\`\`/ossssss+\`\n"
printf "${LCYAN}       -osssssso.      :ssssssso.\n"
printf "${LCYAN}      :osssssss/        osssso+++.\n"
printf "${LCYAN}     /ossssssss/        +ssssooo/-\n"
printf "${LCYAN}   \`/ossssso+/:-        -:/+osssso+-\n"
printf "${LCYAN}  \`+sso+:-\`                 \`.-/+oso:\n"
printf "${LCYAN} \`++:.                           \`-/+/\n"
printf "${LCYAN} .\`                                 \`/\n${NC}"

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
VIRTUAL=$(dmidecode -s system-product-name)
ROOTNAME=$5

#Set variables
if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then
  CPU="iucode-tool intel"
else
  CPU="amd"
fi
if [ "${VIRTUAL}" = "VirtualBox" ]; then
  VIRTUAL="virtualbox-guest-utils virtualbox-guest-dkms"
elif [ "${VIRTUAL}" = "KVM" ]; then
  VIRTUAL="qemu-guest-agent"
else
  VIRTUAL=""
fi

#Install base system + packages
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $CPU)-ucode opendoas networkmanager git $VIRTUAL fish fakeroot which
check_error

#Set localization stuff
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
check_error
arch-chroot /mnt locale-gen
check_error
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
check_error

#Create encryption key
dd bs=512 count=4 if=/dev/random of=/mnt/crypto_keyfile.bin iflag=fullblock
check_error
chmod 600 /mnt/crypto_keyfile.bin
check_error
chmod 600 /mnt/boot/initramfs-linux*
check_error
echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /crypto_keyfile.bin
check_error

#Setup initramfs HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
check_error
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=(/crypto_keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev encrypt autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P
check_error

#Network stuff
arch-chroot /mnt systemctl enable NetworkManager
check_error

#Create user
arch-chroot /mnt useradd -m -s /bin/fish $USER
check_error

#Configure doas
echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf
check_error
echo "permit persist $USER" >> /mnt/etc/doas.conf
arch-chroot /mnt su $USER -c "git clone https://aur.archlinux.org/opendoas-sudo.git /home/$USER/opendoas-sudo"
check_error
mv /mnt/home/$USER/opendoas-sudo/* /mnt
check_error
chmod 777 /mnt
check_error
arch-chroot /mnt su $USER -c "makepkg --noconfirm"
check_error
arch-chroot /mnt pacman -U $(ls /mnt | grep opendoas) --noconfirm
check_error
chmod 755 /mnt
check_error
rm -r /mnt/PKGBUILD /mnt/pkg /mnt/src /mnt/opendoas* /mnt/home/$USER/opendoas-sudo
check_error
ln -sf /mnt/etc/doas.conf /mnt/etc/sudoers
check_error

#Create bootloader
sed -i 's/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' /mnt/etc/default/grub
check_error
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot\"/g" /mnt/etc/default/grub
check_error
if [ "${BOOTTYPE}" = "efi" ]; then
   arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
   check_error
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
   check_error
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
check_error
