#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

print_logo ()
{
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
   printf "${LGREEN}               -~|{*l}*|~\n${NC}" || \
   return 1
}

install_packages ()
{
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
   cp /mnt/etc/fstab fstab.bak && \
   wget https://repo-us.voidlinux.org/live/current/$(curl -s https://repo-us.voidlinux.org/live/current/ | grep void-x86_64-ROOTFS | cut -d '"' -f 2) && \
   tar xvf void-x86_64-ROOTFS-*.tar.xz -C /mnt && \
   mv fstab.bak /mnt/etc/fstab && \
   echo "repository=https://repo-us.voidlinux.org/current" > /mnt/etc/xbps.d/xbps.conf && \
   echo "repository=https://repo-us.voidlinux.org/current/nonfree" >> /mnt/etc/xbps.d/xbps.conf && \
   echo "repository=https://repo-us.voidlinux.org/current/multilib" >> /mnt/etc/xbps.d/xbps.conf && \
   echo "repository=https://repo-us.voidlinux.org/current/multilib/nonfree" >> /mnt/etc/xbps.d/xbps.conf && \
   echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/xbps.conf && \
   echo "ignorepkg=dracut" >> /mnt/etc/xbps.d/xbps.conf && \
   arch-chroot /mnt dhcpcd && \
   arch-chroot /mnt xbps-install -Suy xbps && \
   arch-chroot /mnt xbps-install -uy && \
   arch-chroot /mnt xbps-install -y base-system && \
   arch-chroot /mnt xbps-remove -y base-voidstrap sudo && \
   rm void-x86_64-ROOTFS-*.tar.xz && \
   arch-chroot /mnt xbps-install -Sy linux linux-firmware mkinitcpio mkinitcpio-encrypt $GRUB grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $CPU opendoas NetworkManager git $VIRTUAL cryptsetup fish-shell && \
   arch-chroot /mnt xbps-reconfigure -fa || \
   return 1
}

set_locale ()
{
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/default/libc-locales && \
   arch-chroot /mnt xbps-reconfigure -f glibc-locales && \
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf || \
   return 1
}

create_user ()
{
   arch-chroot /mnt useradd -m -s /bin/fish -G network $USER && \
   mkdir /mnt/home/$USER/.snapshots && \
   echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf && \
   echo "permit persist $USER" >> /mnt/etc/doas.conf && \
   ln -sf /usr/bin/doas /mnt/usr/bin/sudo && \
   ln -sf /etc/doas.conf /mnt/etc/sudoers || \
   return 1
}

set_initramfs ()
{
   echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
   echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
   echo "FILES=(/etc/keys/keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
   if [ "${SWAP}" != "n" ]
   then
      arch-chroot /mnt git clone https://aur.archlinux.org/mkinitcpio-openswap.git && \
      install -Dm 644 /mnt/mkinitcpio-openswap/openswap.hook /mnt/usr/lib/initcpio/hooks/openswap && \
      install -Dm 644 /mnt/mkinitcpio-openswap/openswap.install /mnt/usr/lib/initcpio/install/openswap && \
      install -Dm 644 /mnt/mkinitcpio-openswap/openswap.conf /mnt/etc/openswap.conf && \
      rm -r /mnt/mkinitcpio-openswap && \
      sed -i "s|2788eb78-074d-4424-9f1d-ebffc9c37262|$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)3)|g" /mnt/etc/openswap.conf && \
      sed -i 's|etc/keyfile-cryptswap|etc/keys/keyfile.bin|g' /mnt/etc/openswap.conf && \
      sed -i 's|#keyfile_device_mount_options="--options=subvol=__active/__"|keyfile_device_mount_options="--options=subvol=_active/rootvol"|g' /mnt/etc/openswap.conf && \
      echo "HOOKS=(base udev encrypt openswap autodetect modconf block filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf || \
      return 1
   else
      echo "HOOKS=(base udev encrypt autodetect modconf block filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf || \
      return 1
   fi
   arch-chroot /mnt mkinitcpio -c /etc/mkinitcpio.conf -g /boot/initramfs-$(ls /mnt/usr/lib/modules).img -k $(ls /mnt/usr/lib/modules) && \
   chmod 600 /mnt/boot/initramfs* || \
   return 1
}

create_bootloader ()
{
   echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub && \
   echo "GRUB_CMDLINE_LINUX=\"cryptkey=rootfs:\/etc\/keys\/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot rootflags=subvol=_active/rootvol resume=\/dev\/mapper\/cryptswap\"" >> /mnt/etc/default/grub || \
   return 1
   if [ "${BOOTTYPE}" = "efi" ]; then
      arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck || \
      return 1
   else
      arch-chroot /mnt grub-install /dev/$DISKNAME || \
      return 1
   fi
   arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || \
   return 1
}

distro_clean ()
{
   chmod 1777 /mnt/tmp && \
   chmod 1777 /mnt/var/tmp || \
   return 1
}
