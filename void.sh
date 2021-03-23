#!/bin/sh

check_error ()
{
   if [ $? -ne 0 ]; then
      echo $1
      exit -1
   fi
}

LGREEN='\033[1;32m'
DGRAY='\033[1;30m'
NC='\033[0m'
printf "${LGREEN}                __.;=====;.__\n"
printf "${LGREEN}            _.=+==++=++=+=+===;.\n"
printf "${LGREEN}             -=+++=+===+=+=+++++=_\n"
printf "${LGREEN}        .     -=:\`\`     \`--==+=++==.\n"
printf "${LGREEN}       _vi,    \`            --+=++++:\n"
printf "${LGREEN}      .uvnvi.       _._       -==+==+.\n"
printf "${LGREEN}     .vvnvnI\`    .;==|==;.     :|=||=|.\n"
printf "${DGRAY}+QmQQm${LGREEN}pvvnv; ${DGRAY}_yYsyQQWUUQQQm #QmQ#${LGREEN}:${DGRAY}QQQWUV\$QQm.\n"
printf "${DGRAY} -QQWQW${LGREEN}pvvo${DGRAY}wZ?.wQQQE${LGREEN}==<${DGRAY}QWWQ/QWQW.QQWW${LGREEN}(: ${DGRAY}jQWQE\n"
printf "${DGRAY}  -\$QQQQmmU'  jQQQ@${LGREEN}+=<${DGRAY}QWQQ)mQQQ.mQQQC${LGREEN}+;${DGRAY}jWQQ@'\n"
printf "${DGRAY}   -\$WQ8Y${LGREEN}nI:   ${DGRAY}QWQQwgQQWV${LGREEN}\`${DGRAY}mWQQ.jQWQQgyyWW@!\n"
printf "${LGREEN}     -1vvnvv.     \`~+++\`        ++|+++\n"
printf "${LGREEN}      +vnvnnv,                 \`-|===\n"
printf "${LGREEN}       +vnvnvns.           .      :=-\n"
printf "${LGREEN}        -Invnvvnsi..___..=sv=.     \`\n"
printf "${LGREEN}          +Invnvnvnnnnnnnnvvnn;.\n"
printf "${LGREEN}            ~|Invnvnvvnvvvnnv}+\`\n"
printf "${LGREEN}               -~|{*l}*|~\n${NC}"

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
VIRTUAL=$(dmidecode -s system-product-name)
ROOTNAME=$5

#Set variables
if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then
   CPU="iucode-tool intel-ucode"
else
   CPU="linux-firmware-amd"
fi
if [ "${VIRTUAL}" = "VirtualBox" ]; then
   VIRTUAL="virtualbox-ose-guest virtualbox-ose-guest-dkms"
elif [ "${VIRTUAL}" = "KVM" ]; then
   VIRTUAL="qemu-ga"
else
   VIRTUAL=""
fi
if [ "${BOOTTYPE}" = "efi" ]; then
   GRUB="grub-x86_64-efi"
else
   GRUB="grub"
fi

#Install the base system
cp /mnt/etc/fstab fstab.bak
check_error
wget https://alpha.us.repo.voidlinux.org/live/current/$(curl -s https://alpha.us.repo.voidlinux.org/live/current/ | grep void-x86_64-ROOTFS | cut -d '"' -f 2)
check_error
tar xvf void-x86_64-ROOTFS-*.tar.xz -C /mnt
check_error
mv fstab.bak /mnt/etc/fstab
check_error
echo "repository=https://alpha.us.repo.voidlinux.org/current" > /mnt/etc/xbps.d/xbps.conf
check_error
echo "repository=https://alpha.us.repo.voidlinux.org/current/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/xbps.conf
echo "ignorepkg=dracut" >> /mnt/etc/xbps.d/xbps.conf
arch-chroot /mnt dhcpcd
check_error
arch-chroot /mnt xbps-install -Suy xbps
check_error
arch-chroot /mnt xbps-install -uy
check_error
arch-chroot /mnt xbps-install -y base-system
check_error
arch-chroot /mnt xbps-remove -y base-voidstrap sudo
check_error
rm void-x86_64-ROOTFS-*.tar.xz
check_error

#Install packages
arch-chroot /mnt xbps-install -Sy linux linux-firmware mkinitcpio mkinitcpio-encrypt mkinitcpio-udev $GRUB grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $CPU opendoas NetworkManager git $VIRTUAL cryptsetup fish-shell
check_error
arch-chroot /mnt xbps-reconfigure -fa
check_error

#Set localization stuff
echo "en_US.UTF-8 UTF-8" > /mnt/etc/default/libc-locales
check_error
arch-chroot /mnt xbps-reconfigure -f glibc-locales
check_error
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
check_error

#Network stuff
ln -sf /etc/sv/dbus /mnt/etc/runit/runsvdir/default/
check_error
ln -sf /etc/sv/NetworkManager /mnt/etc/runit/runsvdir/default/
check_error

#Create user
arch-chroot /mnt useradd -m -s /bin/fish -G network $USER
check_error
mkdir /mnt/home/$USER/.snapshots
check_error

#Configure doas
echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf
check_error
echo "permit persist $USER" >> /mnt/etc/doas.conf
ln -sf /usr/bin/doas /mnt/usr/bin/sudo
check_error
ln -sf /etc/doas.conf /mnt/etc/sudoers
check_error

#Create encryption key
dd bs=512 count=4 if=/dev/random of=/mnt/crypto_keyfile.bin iflag=fullblock
check_error
chmod 600 /mnt/crypto_keyfile.bin
check_error
chmod 600 /mnt/boot/initramfs*
check_error
echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /crypto_keyfile.bin
check_error

#Setup initramfs HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
check_error
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=(/crypto_keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev encrypt autodetect modconf block filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -c /etc/mkinitcpio.conf -g /boot/initramfs-$(ls /mnt/usr/lib/modules).img -k $(ls /mnt/usr/lib/modules)
check_error

#Create bootloader
echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
check_error
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot\"" >> /mnt/etc/default/grub
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

#Weird fix
chmod 1777 /mnt/tmp
check_error
chmod 1777 /mnt/var/tmp
check_error
