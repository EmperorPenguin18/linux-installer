#!/bin/bash

LGREEN='\033[1;32m'
DGRAY='\033[1;30m'
printf "${LGREEN}                __.;=====;.__\n"
printf "${LGREEN}            _.=+==++=++=+=+===;.\n"
printf "${LGREEN}             -=+++=+===+=+=+++++=_\n"
printf "${LGREEN}        .     -=:``     `--==+=++==.\n"
printf "${LGREEN}       _vi,    `            --+=++++:\n"
printf "${LGREEN}      .uvnvi.       _._       -==+==+.\n"
printf "${LGREEN}     .vvnvnI`    .;==|==;.     :|=||=|.\n"
printf "${DGRAY}+QmQQm${LGREEN}pvvnv; ${DGRAY}_yYsyQQWUUQQQm #QmQ#${LGREEN}:${DGRAY}QQQWUV\$QQm.\n"
printf "${DGRAY} -QQWQW${LGREEN}pvvo${DGRAY}wZ?.wQQQE${LGREEN}==<${DGRAY}QWWQ/QWQW.QQWW${LGREEN}(: ${DGRAY}jQWQE\n"
printf "${DGRAY}  -\$QQQQmmU'  jQQQ@${LGREEN}+=<${DGRAY}QWQQ)mQQQ.mQQQC${LGREEN}+;${DGRAY}jWQQ@'\n"
printf "${DGRAY}   -\$WQ8Y${LGREEN}nI:   ${DGRAY}QWQQwgQQWV${LGREEN}`${DGRAY}mWQQ.jQWQQgyyWW@!\n"
printf "${LGREEN}     -1vvnvv.     `~+++`        ++|+++\n"
printf "${LGREEN}      +vnvnnv,                 `-|===\n"
printf "${LGREEN}       +vnvnvns.           .      :=-\n"
printf "${LGREEN}        -Invnvvnsi..___..=sv=.     `\n"
printf "${LGREEN}          +Invnvnvnnnnnnnnvvnn;.\n"
printf "${LGREEN}            ~|Invnvnvvnvvvnnv}+`\n"
printf "${LGREEN}               -~|{*l}*|~\n"

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
VIRTUAL=$(dmidecode -s system-product-name)
ROOTNAME=$5

#Set variables
if [[ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]]; then
   CPU="iucode-tool intel-ucode"
else
   CPU="linux-firmware-amd"
fi
if [[ $VIRTUAL = "VirtualBox" ]]; then
   VIRTUAL="virtualbox-ose-guest virtualbox-ose-guest-dkms"
elif [[ $VIRTUAL = "KVM" ]]; then
   VIRTUAL="qemu-ga"
else
   VIRTUAL=""
fi
if [[ $BOOTTYPE = "efi" ]]; then
   GRUB="grub-x86_64-efi"
else
   GRUB="grub"
fi

#Install the base system
cp /mnt/etc/fstab fstab.bak
wget https://alpha.us.repo.voidlinux.org/live/current/$(curl -s https://alpha.us.repo.voidlinux.org/live/current/ | grep void-x86_64-ROOTFS | cut -d '"' -f 2)
tar xvf void-x86_64-ROOTFS-*.tar.xz -C /mnt
mv fstab.bak /mnt/etc/fstab
echo "repository=https://alpha.us.repo.voidlinux.org/current" > /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/xbps.conf
echo "ignorepkg=dracut" >> /mnt/etc/xbps.d/xbps.conf
arch-chroot /mnt ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default/
arch-chroot /mnt dhcpcd
arch-chroot /mnt xbps-install -Suy xbps
arch-chroot /mnt xbps-install -uy
arch-chroot /mnt xbps-install -y base-system
arch-chroot /mnt xbps-remove -y base-voidstrap sudo
rm void-x86_64-ROOTFS-*.tar.xz

#Install packages
arch-chroot /mnt xbps-install -Sy linux linux-firmware mkinitcpio mkinitcpio-encrypt mkinitcpio-udev $GRUB grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $CPU opendoas NetworkManager git $VIRTUAL cryptsetup
arch-chroot /mnt xbps-reconfigure -fa

#Set localization stuff
echo "en_US.UTF-8 UTF-8" > /mnt/etc/default/libc-locales
arch-chroot /mnt xbps-reconfigure -f glibc-locales
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Network stuff
arch-chroot /mnt ln -s /etc/sv/NetworkManager /var/service/

#Create user
arch-chroot /mnt useradd -m -s /bin/bash $USER
mkdir /home/$USER/.snapshots

#Configure doas
echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf
echo "permit persist $USER" >> /mnt/etc/doas.conf
arch-chroot /mnt ln -sf /usr/bin/doas /usr/bin/sudo
arch-chroot /mnt ln -s /etc/doas.conf /etc/sudoers

#Create encryption key
arch-chroot /mnt dd bs=512 count=4 if=/dev/random of=/crypto_keyfile.bin iflag=fullblock
arch-chroot /mnt chmod 600 /crypto_keyfile.bin
arch-chroot /mnt chmod 600 /boot/$(ls /mnt/boot | grep initramfs)
echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /crypto_keyfile.bin

#Setup initramfs HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=(/crypto_keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev encrypt autodetect modconf block filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -c /etc/mkinitcpio.conf -g /boot/initramfs-$(ls /mnt/usr/lib/modules).img -k $(ls /mnt/usr/lib/modules)

#Create bootloader
echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot\"" >> /mnt/etc/default/grub
if [[ $BOOTTYPE = "efi" ]]; then
   arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
else
   arch-chroot /mnt grub-install /dev/$DISKNAME
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
