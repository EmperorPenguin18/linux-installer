#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

check_error ()
{
   if [ $? -ne 0 ]; then
      echo $1
      exit -1
   fi
}

PURPLE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
printf "          ${PURPLE}/:-------------:\\n"
printf "       ${PURPLE}:-------------------::\n"
printf "     ${PURPLE}:-----------${WHITE}/shhOHbmp${PURPLE}---:\\n"
printf "   ${PURPLE}/-----------${WHITE}omMMMNNNMMD${PURPLE}  ---:\n"
printf "  ${PURPLE}:-----------${WHITE}sMMMMNMNMP${PURPLE}.    ---:\n"
printf " ${PURPLE}:-----------${WHITE}:MMMdP${PURPLE}-------    ---\\n"
printf "${PURPLE},------------${WHITE}:MMMd${PURPLE}--------    ---:\n"
printf "${PURPLE}:------------${WHITE}:MMMd${PURPLE}-------    .---:\n"
printf "${PURPLE}:----    ${WHITE}oNMMMMMMMMMNho${PURPLE}     .----:\n"
printf "${PURPLE}:--     .${WHITE}+shhhMMMmhhy++${PURPLE}   .------/\n"
printf "${PURPLE}:-    -------${WHITE}:MMMd${PURPLE}--------------:\n"
printf "${PURPLE}:-   --------${WHITE}/MMMd${PURPLE}-------------;\n"
printf "${PURPLE}:-    ------${WHITE}/hMMMy${PURPLE}------------:\n"
printf "${PURPLE}:-- ${WHITE}:dMNdhhdNMMNo${PURPLE}------------;\n"
printf "${PURPLE}:---${WHITE}:sdNMMMMNds:${PURPLE}------------:\n"
printf "${PURPLE}:------${WHITE}:://:${PURPLE}-------------::\n"
printf "${PURPLE}:---------------------://\n${NC}"

BOOTTYPE=$1
PASS=$2
USER=$3
DISKNAME=$4
VIRTUAL=$(dmidecode -s system-product-name)
ROOTNAME=$5

#Set variables
if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then CPU="iucode-tool"; fi
if [ "${VIRTUAL}" = "KVM" ]; then
   VIRTUAL="qemu-guest-agent"
else
   VIRTUAL=""
fi
if [ "${BOOTTYPE}" = "efi" ]; then
   GRUB=""
else
   GRUB="grub2-pc os-prober"
fi

#Get DNF
if [ "$(df | grep /run/archiso/cowspace | wc -l)" -gt 0 ]; then mount -o remount,size=2G /run/archiso/cowspace; fi
check_error
wget -O - https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/34/Cloud/x86_64/images/$(curl -Ls https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/34/Cloud/x86_64/images/ | cut -d '"' -f 2 | grep raw.xz) | xzcat >fedora.img
check_error
DEVICE=$(losetup --show -fP fedora.img)
check_error
mkdir -p /loop
check_error
mount $(echo $DEVICE)p1 /loop
check_error
mkdir /media
check_error
cp -ax /loop /media
check_error
umount /loop
check_error
losetup -d $DEVICE
check_error
rm fedora.img
check_error

#Install the base system
mount -o bind /mnt /media/loop/mnt
check_error
sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot
check_error
arch-chroot /media/loop dnf install -y --installroot=/mnt --releasever=34 --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck basesystem dnf glibc-langpack-en glibc-locale-source iputils NetworkManager
check_error
arch-chroot /mnt localedef -c -i en_US -f UTF-8 en_US-UTF-8
check_error

#Install packages
arch-chroot /mnt dnf install -y --setopt=install_weak_deps=False --setopt=keepcache=True kernel $GRUB passwd linux-firmware btrfs-progs dosfstools $CPU microcode_ctl git $VIRTUAL cryptsetup-luks sudo fish
check_error

#Create user
arch-chroot /mnt useradd -m -s /bin/fish -G wheel $USER
check_error
echo "root ALL=(ALL) ALL" > /mnt/etc/sudoers
check_error
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

#Setup initramfs
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$ROOTNAME) /etc/keys/keyfile.bin luks" > /mnt/etc/crypttab
check_error
echo 'install_items+=" /etc/keys/keyfile.bin /etc/crypttab "' > /mnt/etc/dracut.conf.d/10-crypt.conf
check_error

#Create bootloader
if [ "${BOOTTYPE}" = "efi" ]; then
   arch-chroot /mnt bootctl install
   check_error
   echo "default  fedora.conf" > /mnt/boot/loader/loader.conf
   check_error
   echo "timeout  4" >> /mnt/boot/loader/loader.conf
   echo "editor   no" >> /mnt/boot/loader/loader.conf
   arch-chroot /mnt dnf reinstall -y kernel-core
   check_error
   rm /mnt/boot/loader/entries/*
   check_error
   rm /mnt/boot/loader/random-seed
   check_error
   find /mnt/boot -name "linux" -exec mv -t /mnt/boot {} +
   check_error
   find /mnt/boot -name "initrd" -exec mv -t /mnt/boot {} +
   check_error
   find /mnt/boot -name "*x86_64" -exec rmdir -p {} + 2>/dev/null
   echo "title Fedora" > /mnt/boot/loader/entries/fedora.conf
   check_error
   echo "linux /linux" >> /mnt/boot/loader/entries/fedora.conf
   echo "initrd   /initrd" >> /mnt/boot/loader/entries/fedora.conf
   echo "options  cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot root=/dev/mapper/cryptroot rootflags=subvol=/_active/rootvol rw" >> /mnt/boot/loader/entries/fedora.conf
else
   echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
   check_error
   echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot root=UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot) rootflags=subvol=/_active/rootvol rw\"" >> /mnt/etc/default/grub
   check_error
   arch-chroot /mnt grub2-mkconfig -o /boot/grub2/grub.cfg
   check_error
   arch-chroot /mnt grub2-install /dev/$DISKNAME
   check_error
   arch-chroot /mnt dracut --force --regenerate-all
   check_error
fi

#Clean
umount /media/loop/mnt
check_error
rm -r /media/loop
check_error
