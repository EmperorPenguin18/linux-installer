#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

print_logo ()
{
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
   printf "${LCYAN} .\`                                 \`/\n${NC}" || \
   return 1
}

install_packages ()
{
   VIRTUAL=$(dmidecode -s system-product-name)
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
   pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $CPU)-ucode opendoas networkmanager git $VIRTUAL fish fakeroot which binutils || \
   return 1
}

set_locale ()
{
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen && \
   arch-chroot /mnt locale-gen && \
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf || \
   return 1
}

set_initramfs ()
{
   echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
   echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
   echo "FILES=(/etc/keys/keyfile.bin)" >> /mnt/etc/mkinitcpio.conf
   if [ "${SWAP}" != "n" ]
   then
      arch-chroot /mnt su $USER -c "git clone https://aur.archlinux.org/mkinitcpio-openswap.git /home/$USER/mkinitcpio-openswap" && \
      mv /mnt/home/$USER/mkinitcpio-openswap/* /mnt && \
      chmod 777 /mnt && \
      arch-chroot /mnt su $USER -c "makepkg --noconfirm" && \
      arch-chroot /mnt pacman -U $(ls /mnt | grep mkinitcpio) --noconfirm && \
      chmod 755 /mnt && \
      rm -r /mnt/PKGBUILD /mnt/pkg /mnt/src /mnt/mkinitcpio* /mnt/openswap* /mnt/usage.install /mnt/LICENSE /mnt/home/$USER/mkinitcpio-openswap && \
      sed -i "s|2788eb78-074d-4424-9f1d-ebffc9c37262|$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)3)|g" /mnt/etc/openswap.conf && \
      sed -i 's|etc/keyfile-cryptswap|etc/keys/keyfile.bin|g' /mnt/etc/openswap.conf && \
      sed -i 's|#keyfile_device_mount_options="--options=subvol=__active/__"|keyfile_device_mount_options="--options=subvol=_active/rootvol"|g' /mnt/etc/openswap.conf && \
      echo "HOOKS=(base udev encrypt openswap autodetect modconf block filesystems keyboard resume fsck)" >> /mnt/etc/mkinitcpio.conf || \
      return 1
   else
      echo "HOOKS=(base udev encrypt autodetect modconf block filesystems keyboard resume fsck)" >> /mnt/etc/mkinitcpio.conf || \
      return 1
   fi
   arch-chroot /mnt mkinitcpio -P && \
   chmod 600 /mnt/boot/initramfs-linux* || \
   return 1
}

create_user ()
{
   arch-chroot /mnt useradd -m -s /bin/fish -G video $USER && \
   echo "#This system uses doas instead of sudo" > /mnt/etc/doas.conf && \
   echo "permit persist $USER" >> /mnt/etc/doas.conf && \
   arch-chroot /mnt su $USER -c "git clone https://aur.archlinux.org/opendoas-sudo.git /home/$USER/opendoas-sudo" && \
   mv /mnt/home/$USER/opendoas-sudo/* /mnt && \
   chmod 777 /mnt && \
   arch-chroot /mnt su $USER -c "makepkg --noconfirm" && \
   arch-chroot /mnt pacman -U $(ls /mnt | grep opendoas) --noconfirm && \
   chmod 755 /mnt && \
   rm -r /mnt/PKGBUILD /mnt/pkg /mnt/src /mnt/opendoas* /mnt/home/$USER/opendoas-sudo && \
   ln -sf /etc/doas.conf /mnt/etc/sudoers || \
   return 1
}

create_bootloader ()
{
   sed -i 's/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' /mnt/etc/default/grub
   sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptkey=rootfs:\/etc\/keys\/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot resume=/dev/mapper/cryptswap\"/g" /mnt/etc/default/grub || \
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
   return 0
}
