#Check if script has root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

#Set system time
timedatectl set-ntp true

#Partition disk
pacman -S dmidecode --noconfirm
DISKNAME=$(lsblk | grep disk | awk '{print $1;}')
DISKSIZE=$(lsblk --output SIZE -n -d /dev/$DISKNAME | sed 's/.$//')
MEMSIZE=$(dmidecode -t 17 | grep "Size.*MB" | awk '{s+=$2} END {print s / 1024}')
parted --script /dev/$DISKNAME \
   mklabel gpt \
   mkpart P1 fat32 1MB 261MB \
   set 1 esp on \
   mkpart P2 btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)GB \
   mkpart P3 linux-swap $(expr $DISKSIZE - $MEMSIZE)GB $(echo $DISKSIZE)GB
if [ $(echo $DISKNAME | head -c 2 ) = "sd" ]; then
   DISKNAME=$DISKNAME
else
   DISKNAME=$(echo $DISKNAME)p
fi

#Format partitions
mkfs.fat -F32 /dev/$(echo $DISKNAME)1
mkfs.btrfs -L arch /dev/$(echo $DISKNAME)2
mkswap /dev/$(echo $DISKNAME)3
swapon /dev/$(echo $DISKNAME)3
mount /dev/$(echo $DISKNAME)2 /mnt

#BTRFS subvolumes
cd /mnt
btrfs subvolume create _active
btrfs subvolume create _active/rootvol
btrfs subvolume create _active/homevol
btrfs subvolume create _active/tmp
btrfs subvolume create _snapshots
cd /root/LinuxConfigs

#Mount subvolumes for install
umount /mnt
mount -o subvol=_active/rootvol /dev/$(echo $DISKNAME)2 /mnt
mkdir /mnt/{home,tmp,boot}
mkdir /mnt/boot/EFI
mount -o subvol=_active/tmp /dev/$(echo $DISKNAME)2 /mnt/tmp
mount /dev/$(echo $DISKNAME)1 /mnt/boot/EFI
mount -o subvol=_active/homevol /dev/$(echo $DISKNAME)2 /mnt/home

#Configure mirrors
pacman -S reflector --noconfirm
reflector --country Canada --protocol https --sort rate --save /etc/pacman.d/mirrorlist

#Install packages
pacman -Sy
pacstrap /mnt base linux linux-firmware linux-headers sudo vim grub grub-btrfs efibootmgr dosfstools os-prober mtools parted reflector btrfs-progs amd-ucode intel-ucode dmidecode networkmanager git
#*doas*
#*VM support*

#Generate FSTAB
UUID1=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)1)
UUID2=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)2)
UUID3=$(blkid -s UUID -o value /dev/$(echo $DISKNAME)3)
echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
echo UUID=$UUID1 /boot/EFI   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 >> /mnt/etc/fstab
echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
echo UUID=$UUID3 none  swap  defaults 0  0 >> /mnt/etc/fstab
echo UUID=$UUID2 /home/sebastien/.snapshots btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab

#Add btrfs to HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=()" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/America/Toronto /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "en_CA.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_CA.UTF-8" > /mnt/etc/locale.conf

#Network stuff
echo "Sebs-PC" > /mnt/etc/hostname
echo "127.0.0.1   localhost" > /mnt/etc/hosts
echo "::1   localhost" >> /mnt/etc/hosts
echo "127.0.1.1   Sebs-PC.localdomain  Sebs-PC" >> /mnt/etc/hosts
arch-chroot /mnt systemctl enable NetworkManager

#Create root password
arch-chroot /mnt passwd

#Create user
arch-chroot /mnt useradd -m sebastien
arch-chroot /mnt passwd sebastien
arch-chroot /mnt usermod -aG wheel,audio,video,optical,storage sebastien
arch-chroot /mnt echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

#Create bootloader
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=GRUB --recheck
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

#Done
reboot
#*Encrypted disk*
