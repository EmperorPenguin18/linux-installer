#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

print_logo ()
{
   RED='\033[1;31m'
   NC='\033[0m'
   printf "${RED}       _,met\$\$\$\$\$gg.\n"
   printf "${RED}    ,g\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$P.\n"
   printf "${RED}  ,g\$\$P\"     \"\"\"Y\$\$.\".\n"
   printf "${RED} ,\$\$P'              \`\$\$\$.\n"
   printf "${RED}',\$\$P       ,ggs.     \`\$\$b:\n"
   printf "${RED}\`d\$\$'     ,\$P\"'   .    \$\$\$\n"
   printf "${RED} \$\$P      d\$'     ,    \$\$P\n"
   printf "${RED} \$\$:      \$\$.   -    ,d\$\$'\n"
   printf "${RED} \$\$;      Y\$b._   _,d\$P'\n"
   printf "${RED} Y\$\$.    \`.\`\"Y\$\$\$\$P\"'\n"
   printf "${RED} \`\$\$b      \"-.__\n"
   printf "${RED}  \`Y\$\$\n"
   printf "${RED}   \`Y\$\$.\n"
   printf "${RED}     \`\$\$b.\n"
   printf "${RED}       \`Y\$\$b.\n"
   printf "${RED}          \`\"Y\$b._\n"
   printf "${RED}              \`\"\"\"\n${NC}"
}

install_packages ()
{
   if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then
      CPU="iucode-tool intel"
   else
      CPU="amd64"
   fi
   if [ "${BOOTTYPE}" = "efi" ]; then
      GRUB=""
   else
      GRUB="grub2"
   fi
   pacman -S debootstrap debian-archive-keyring --noconfirm && \
   debootstrap --arch amd64 stable /mnt http://deb.debian.org/debian && \
   sed -i '$s|^|DEBIAN_FRONTEND=noninteractive PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot && \
   arch-chroot /mnt apt update && arch-chroot /mnt apt install -y gnupg locales && \
   sed -e '/#/d' -i /mnt/etc/apt/sources.list && sed -e 's/main/main contrib non-free/' -i /mnt/etc/apt/sources.list && \
   echo 'deb http://deb.xanmod.org releases main' | tee /mnt/etc/apt/sources.list.d/xanmod-kernel.list && wget -qO - https://dl.xanmod.org/gpg.key | arch-chroot /mnt apt-key add - && \
   arch-chroot /mnt apt update && \
   arch-chroot /mnt apt install -y linux-xanmod-edge firmware-linux $GRUB btrfs-progs dosfstools $(echo $CPU)-microcode network-manager git cryptsetup sudo fish && \
   arch-chroot /mnt apt purge -y nano vim-common && \
   arch-chroot /mnt apt upgrade -y && \
   arch-chroot /mnt dpkg-reconfigure $(arch-chroot /mnt dpkg-query -l | grep linux-image | awk '{print $2}') $GRUB || \
   return 1
}

set_locale ()
{
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen && \
   arch-chroot /mnt locale-gen && \
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf || \
   return 1
}

create_user ()
{
   arch-chroot /mnt addgroup wheel && \
   arch-chroot /mnt useradd -m -s /usr/bin/fish -G wheel $USER && \
   echo "root ALL=(ALL) ALL" > /mnt/etc/sudoers && \
   echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers || \
   return 1
}

set_initramfs ()
{
   echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$ROOTNAME) /etc/keys/keyfile.bin luks,discard,key-slot=1" > /mnt/etc/crypttab && \
   echo "cryptswap UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)3) /etc/keys/keyfile.bin luks,swap,key-slot=1" >> /mnt/etc/crypttab && \
   echo "KEYFILE_PATTERN=\"/etc/keys/key*\"" >> /mnt/etc/cryptsetup-initramfs/conf-hook && \
   echo "UMASK=0077" >> /mnt/etc/initramfs-tools/initramfs.conf && \
   arch-chroot /mnt update-initramfs -u || \
   return 1
}

create_bootloader ()
{
   if [ "${BOOTTYPE}" = "efi" ]; then
      arch-chroot /mnt bootctl install && \
      echo "default  debian.conf" > /mnt/boot/loader/loader.conf && \
      echo "timeout  4" >> /mnt/boot/loader/loader.conf && \
      echo "editor   no" >> /mnt/boot/loader/loader.conf && \
      echo "title Debian" > /mnt/boot/loader/entries/debian.conf && \
      echo "linux /$(ls /mnt/boot | grep vmlinuz)" >> /mnt/boot/loader/entries/debian.conf && \
      echo "initrd   /$(ls /mnt/boot | grep .img)" >> /mnt/boot/loader/entries/debian.conf && \
      echo "options  cryptkey=rootfs:/etc/keys/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot resume=/dev/mapper/cryptswap root=dev/mapper/cryptroot rootflags=subvol=/_active/rootvol rw" >> /mnt/boot/loader/entries/debian.conf || \
      return 1
   else
      echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub && \
      sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptkey=rootfs:\/etc\/keys\/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot resume=\/dev\/mapper\/cryptswap\"/g" /mnt/etc/default/grub && \
      arch-chroot /mnt grub-install /dev/$DISKNAME && \
      arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || \
      return 1
   fi
}

distro_clean ()
{
   return 0
}
