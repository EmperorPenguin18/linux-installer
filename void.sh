#!/bin/bash

#                __.;=====;.__
#            _.=+==++=++=+=+===;.
#             -=+++=+===+=+=+++++=_
#        .     -=:``     `--==+=++==.
#       _vi,    `            --+=++++:
#      .uvnvi.       _._       -==+==+.
#     .vvnvnI`    .;==|==;.     :|=||=|.
#+QmQQmpvvnv; _yYsyQQWUUQQQm #QmQ#:QQQWUV$QQm.
# -QQWQWpvvowZ?.wQQQE==<QWWQ/QWQW.QQWW(: jQWQE
#  -$QQQQmmU'  jQQQ@+=<QWQQ)mQQQ.mQQQC+;jWQQ@'
#   -$WQ8YnI:   QWQQwgQQWV`mWQQ.jQWQQgyyWW@!
#     -1vvnvv.     `~+++`        ++|+++
#      +vnvnnv,                 `-|===
#       +vnvnvns.           .      :=-
#        -Invnvvnsi..___..=sv=.     `
#          +Invnvnvnnnnnnnnvvnn;.
#            ~|Invnvnvvnvvvnnv}+`
#               -~|{*l}*|~

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
   cpu="iucode-tool intel-ucode"
else
   cpu="linux-firmware-amd"
fi
if [[ $virtual = "VirtualBox" ]]; then
   virtual="virtualbox-ose-guest virtualbox-ose-guest-dkms"
elif [[ $virtual = "KVM" ]]; then
   virtual="qemu-ga"
else
   virtual=""
fi
if [[ $BOOTTYPE = "efi" ]]; then
   grub="grub-x86_64-efi"
else
   grub="grub"
fi

#Install the base system
wget https://alpha.us.repo.voidlinux.org/live/current/$(curl -s https://alpha.us.repo.voidlinux.org/live/current/ | grep void-x86_64-ROOTFS | cut -d '"' -f 2)
tar xvf void-x86_64-ROOTFS-*.tar.xz -C /mnt
echo "repository=https://alpha.us.repo.voidlinux.org/current" > /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib" >> /mnt/etc/xbps.d/xbps.conf
echo "repository=https://alpha.us.repo.voidlinux.org/current/multilib/nonfree" >> /mnt/etc/xbps.d/xbps.conf
echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/xbps.conf
arch-chroot /mnt ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default/
arch-chroot /mnt dhcpcd
arch-chroot /mnt xbps-install -Suy xbps
arch-chroot /mnt xbps-install -uy
arch-chroot /mnt xbps-install -y base-system
arch-chroot /mnt xbps-remove -y base-voidstrap

#Install packages
arch-chroot /mnt xbps-install -Sy linux-firmware $grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $cpu opendoas NetworkManager git $virtual
arch-chroot /mnt xbps-reconfigure -fa

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /mnt/etc/default/libc-locales
arch-chroot /mnt xbps-reconfigure -f glibc-locales
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Network stuff
echo $host > /mnt/etc/hostname
echo "127.0.0.1   localhost" > /mnt/etc/hosts
echo "::1   localhost" >> /mnt/etc/hosts
echo "127.0.1.1   $(echo $host).localdomain  $host" >> /mnt/etc/hosts
arch-chroot /mnt ln -s /etc/sv/NetworkManager /var/service/

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
