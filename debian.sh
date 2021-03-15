#!/bin/sh

check_error ()
{
   if [ $? -ne 0 ]; then
      echo $1
      exit -1
   fi
}

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

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
ROOTNAME=$5

#Set variables
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

#Install base system to mounted disk
pacman -S debootstrap debian-archive-keyring --noconfirm
check_error
debootstrap --arch amd64 buster /mnt http://deb.debian.org/debian
check_error
sed -i '$s|^|DEBIAN_FRONTEND=noninteractive PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
check_error
arch-chroot /mnt apt update && arch-chroot /mnt apt install -y gnupg locales
check_error

#Set locale
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
check_error
arch-chroot /mnt locale-gen
check_error
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
check_error

#Install packages
sed -e '/#/d' -i /mnt/etc/apt/sources.list && sed -e 's/main/main contrib non-free/' -i /mnt/etc/apt/sources.list
check_error
echo 'deb http://deb.xanmod.org releases main' | tee /mnt/etc/apt/sources.list.d/xanmod-kernel.list && wget -qO - https://dl.xanmod.org/gpg.key | arch-chroot /mnt apt-key add -
check_error
arch-chroot /mnt apt update
check_error
arch-chroot /mnt apt install -y linux-xanmod-edge firmware-linux $GRUB btrfs-progs dosfstools $(echo $CPU)-microcode network-manager git cryptsetup sudo fish
check_error

#Clean up install
arch-chroot /mnt apt purge -y nano vim-common
check_error
arch-chroot /mnt apt upgrade -y
check_error
arch-chroot /mnt dpkg-reconfigure $(arch-chroot /mnt dpkg-query -l | grep linux-image | awk '{print $2}') $GRUB
check_error

#Network stuff
arch-chroot /mnt systemctl enable NetworkManager
check_error

#Create user
arch-chroot /mnt addgroup wheel
check_error
arch-chroot /mnt useradd -m -s /bin/fish -G wheel $USER
check_error
echo "root ALL=(ALL) ALL" > /mnt/etc/sudoers
check_error
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

#Create encryption key
mkdir -m 0700 /mnt/etc/keys
check_error
dd if=/dev/urandom bs=1 count=64 of=/mnt/etc/keys/root.key conv=excl,fsync
check_error
echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /etc/keys/root.key
check_error
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$ROOTNAME) /etc/keys/root.key luks,discard,key-slot=1" > /mnt/etc/crypttab
check_error
echo "KEYFILE_PATTERN=\"/etc/keys/*.key\"" >> /mnt/etc/cryptsetup-initramfs/conf-hook
check_error
echo "UMASK=0077" >> /mnt/etc/initramfs-tools/initramfs.conf
check_error
arch-chroot /mnt update-initramfs -u
check_error

#Create bootloader
if [ "${BOOTTYPE}" = "efi" ]; then
   arch-chroot /mnt bootctl install
   check_error
   echo "default  debian.conf" > /mnt/boot/loader/loader.conf
   check_error
   echo "timeout  4" >> /mnt/boot/loader/loader.conf
   echo "editor   no" >> /mnt/boot/loader/loader.conf
   echo "title Debian" > /mnt/boot/loader/entries/debian.conf
   check_error
   echo "linux /$(ls /mnt/boot | grep vmlinuz)" >> /mnt/boot/loader/entries/debian.conf
   echo "initrd   /$(ls /mnt/boot | grep .img)" >> /mnt/boot/loader/entries/debian.conf
   echo "options  cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot root=dev/mapper/cryptroot rootflags=subvol=/_active/rootvol rw" >> /mnt/boot/loader/entries/debian.conf
else
   echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
   check_error
   sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot\"/g" /mnt/etc/default/grub
   check_error
   arch-chroot /mnt grub-install /dev/$DISKNAME
   check_error
   arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
   check_error
fi
