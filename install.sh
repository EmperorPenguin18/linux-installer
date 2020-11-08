#Checks before starting
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi
if [ $(ls /usr/bin | grep pacman | wc -l) -lt 1 ]; then
   echo "This is not an Arch system"
   exit 1
fi
if [ $(lsblk | wc -l) -gt 3 ]; then
   echo "Drives aren't set up right"
   exit 1
fi

#Prompts
echo "-------------------------------------------------"
echo "           Welcome to linux-installer!           "
echo "-------------------------------------------------"
echo "Please answer the following questions to begin:"
swap=$(read -p "Do you want hibernation enabled (Swap partition) [Y/n] ")
distro=$(read -p "What distro do you want to install? Default is Arch. [arch/debian/fedora/void] ")
time=$(read -p "Choose a timezone (eg America/Toronto). >")
host=$(read -p "What will the hostname of this computer be? >")
rpass=$(read -p "Enter the root password. >")
user=$(read -p "Enter your username. >")
upass=$(read -p "Enter your user password. >")

#Set system time
timedatectl set-ntp true

#Partition disk
pacman -S dmidecode --noconfirm
DISKNAME=$(lsblk | grep disk | awk '{print $1;}')
DISKSIZE=$(lsblk --output SIZE -n -d /dev/$DISKNAME | sed 's/.$//')
MEMSIZE=$(dmidecode -t 17 | grep "Size.*MB" | awk '{s+=$2} END {print s / 1024}')
if [ $swap = "n" ]; then
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart P1 fat32 1MB 261MB \
      set 1 esp on \
      mkpart P2 btrfs 261MB $(echo $DISKSIZE)GB \
else
   parted --script /dev/$DISKNAME \
      mklabel gpt \
      mkpart P1 fat32 1MB 261MB \
      set 1 esp on \
      mkpart P2 btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)GB \
      mkpart P3 linux-swap $(expr $DISKSIZE - $MEMSIZE)GB $(echo $DISKSIZE)GB
fi
if [ $(echo $DISKNAME | head -c 2 ) = "sd" ]; then
   DISKNAME=$DISKNAME
else
   DISKNAME=$(echo $DISKNAME)p
fi

#Format partitions
mkfs.fat -F32 /dev/$(echo $DISKNAME)1
mkfs.btrfs -L arch /dev/$(echo $DISKNAME)2
if [ $swap != "n" ]; then
   mkswap /dev/$(echo $DISKNAME)3
   swapon /dev/$(echo $DISKNAME)3
fi
mount /dev/$(echo $DISKNAME)2 /mnt

#BTRFS subvolumes
btrfs subvolume create /mnt/_active
btrfs subvolume create /mnt/_active/rootvol
btrfs subvolume create /mnt/_active/homevol
btrfs subvolume create /mnt/_active/tmp
btrfs subvolume create /mnt/_snapshots

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
pacman -Sy

#Install packages
if [ $(cat /proc/cpuinfo | grep name | grep Intel | wc -l) -gt 0 ]; then cpu="intel"; else cpu="amd"; fi
virtual=$(dmidecode -s system-product-name)
if [ $virtual = "VirtualBox" ]; then
   virtual="virtualbox-guest-utils virtualbox-guest-dkms"
elif [ $virtual = "KVM" ]; then
   virtual="qemu-guest-agent"
else
   virtual=""
fi
if [ $distro = "debian" ]; then
   pacman -S debootstrap
   #*
elif [ $distro = "fedora" ]; then
   chmod 777 ./
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
   cd ../
   su nobody -c "git clone https://aur.archlinux.org/dnf.git"
   cd dnf
   su nobody -c "makepkg -si --noconfirm"
   cd ../
   rm -r dnf
   cd linux-installer
   #*
elif [ $distro = "void" ]; then
   chmod 777 ./
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
   echo "%nobody ALL=(ALL) NOPASSWD: /usr/bin/makepkg" >> /etc/sudoers
   cd ../
   su nobody -c "git clone https://aur.archlinux.org/xbps.git"
   cd xbps
   su nobody -c "makepkg -si --noconfirm"
   cd ../
   rm -r xpbs
   cd linux-installer
   #*
else
   pacstrap /mnt base linux-zen linux-zen-headers linux-firmware grub grub-btrfs efibootmgr os-prober btrfs-progs dosfstools $(echo $cpu)-ucode opendoas networkmanager git $virtual
fi
#*Distro*

#Generate FSTAB
UUID1=$(arch-chroot /mnt blkid -s UUID -o value /dev/$(echo $DISKNAME)1)
UUID2=$(arch-chroot /mnt blkid -s UUID -o value /dev/$(echo $DISKNAME)2)
if [ $swap != "n" ]; then
   UUID3=$(arch-chroot /mnt blkid -s UUID -o value /dev/$(echo $DISKNAME)3)
   echo UUID=$UUID3 none  swap  defaults 0  0 >> /mnt/etc/fstab
fi
echo UUID=$UUID1 /boot/EFI   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 >> /mnt/etc/fstab
if [ $(lsblk -d -o name,rota | grep $DISKNAME | grep 1 | wc -l) -eq 1 ]; then
   echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home/$(echo $user)/.snapshots btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
else
   echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
   echo UUID=$UUID2 /home/$(echo $user)/.snapshots btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
fi

#Add btrfs to HOOKS
echo "MODULES=()" > /mnt/etc/mkinitcpio.conf
echo "BINARIES=()" >> /mnt/etc/mkinitcpio.conf
echo "FILES=()" >> /mnt/etc/mkinitcpio.conf
echo "HOOKS=(base udev autodetect modconf block btrfs filesystems keyboard fsck)" >> /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

#Set localization stuff
ln -sf /mnt/usr/share/zoneinfo/$(echo $time) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

#Network stuff
echo $host > /mnt/etc/hostname
echo "127.0.0.1   localhost" > /mnt/etc/hosts
echo "::1   localhost" >> /mnt/etc/hosts
echo "127.0.1.1   $(echo $host).localdomain  $host" >> /mnt/etc/hosts
arch-chroot /mnt systemctl enable NetworkManager

#Create root password
arch-chroot /mnt echo $rpass | chpasswd --stdin

#Create user
arch-chroot /mnt useradd -m $user
arch-chroot /mnt echo $upass | chpasswd --stdin $user
arch-chroot /mnt usermod -aG audio,video,optical,storage $user
arch-chroot /mnt echo "permit persist $user" > /etc/doas.conf

#Create bootloader
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=GRUB --recheck
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

#Done
reboot
#*Encrypted disk*
