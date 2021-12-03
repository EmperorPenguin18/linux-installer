#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

pre_checks ()
{
   timedatectl set-ntp true
   clear
   if [ "$(id -u)" -ne 0 ]; then
      echo "This script must be run as root" 
      exit 1
   fi
   if [ "$(ls /usr/bin | grep pacman | wc -l)" -lt 1 ]; then
      echo "This is not an Arch system"
      exit 1
   fi
   if ping -q -c 1 -W 1 google.com >/dev/null; then
      echo "The network is up"
   else
      echo "The network is down"
      exit 1
   fi
   pacman -Sy >/dev/null 2>&1
   pacman -Q | awk '{print $1}' > pre.txt
   pacman -S dmidecode parted dosfstools util-linux reflector arch-install-scripts efibootmgr dialog wget cryptsetup bc --noconfirm --needed >/dev/null 2>&1 
}

setup_partitions ()
{
   echo "Wiping all data on disk..."
   dd if=/dev/zero of=/dev/$DISKNAME bs=4096 status=progress
   if [ "$(efibootmgr | wc -l)" -gt 0 ]; then
      BOOTTYPE="efi"
   else
      BOOTTYPE="legacy"
      echo "Using legacy boot"
   fi
   DISKSIZE=$(lsblk --output SIZE -n -d -b /dev/$DISKNAME)
   DISKSIZE=$(printf "$DISKSIZE / 1024 / 1024\n" | bc)
   MEMSIZE=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
   MEMSIZE=$(printf "$MEMSIZE * 1.5 / 1024\n" | bc)
   if [ "$(expr length $DISKNAME)" -eq 3 ]; then
      DISKNAME2=$DISKNAME
   else
      DISKNAME2=$(echo $DISKNAME)p
   fi
   ROOTNAME=$(echo $DISKNAME2)2
}

partition_drive ()
{
   if [ "${SWAP}" = "n" ] && [ "${BOOTTYPE}" = "efi" ]; then
      parted --script /dev/$DISKNAME \
         mklabel gpt \
         mkpart boot fat32 1MB 261MB \
         set 1 esp on \
         mkpart root btrfs 261MB $(echo $DISKSIZE)MB || \
      return 1
   elif [ "${SWAP}" = "n" ]; then
      parted --script /dev/$DISKNAME \
         mklabel msdos \
         mkpart primary fat32 1MB 261MB \
         set 1 boot on \
         mkpart primary btrfs 261MB $(echo $DISKSIZE)MB || \
      return 1
   elif [ "${BOOTTYPE}" = "efi" ]; then
      parted --script /dev/$DISKNAME \
         mklabel gpt \
         mkpart boot fat32 1MB 261MB \
         set 1 esp on \
         mkpart root btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)MB \
         mkpart swap linux-swap $(expr $DISKSIZE - $MEMSIZE)MB $(echo $DISKSIZE)MB || \
      return 1
   else
      parted --script /dev/$DISKNAME \
         mklabel msdos \
         mkpart primary fat32 1MB 261MB \
         set 1 boot on \
         mkpart primary btrfs 261MB $(expr $DISKSIZE - $MEMSIZE)MB \
         mkpart primary linux-swap $(expr $DISKSIZE - $MEMSIZE)MB $(echo $DISKSIZE)MB || \
      return 1
   fi
}

encrypt_partitions ()
{
   echo "$PASS" | cryptsetup -q luksFormat --type luks1 /dev/$ROOTNAME && \
   echo "$PASS" | cryptsetup -q luksFormat --type luks1 /dev/$(echo $DISKNAME2)3 &&\
   echo "$PASS" | cryptsetup open /dev/$ROOTNAME cryptroot && \
   echo "$PASS" | cryptsetup open /dev/$(echo $DISKNAME2)3 cryptswap || \
   return 1
}

format_partitions ()
{
   mkfs.fat -F 32 /dev/$(echo $DISKNAME2)1 && \
   mkfs.btrfs /dev/mapper/cryptroot && \
   mount /dev/mapper/cryptroot /mnt || \
   return 1
   if [ "${SWAP}" != "n" ]; then
      mkswap /dev/mapper/cryptswap && \
      swapon /dev/mapper/cryptswap || \
      return 1
   fi
}

mount_subvolumes ()
{
   pth=$(pwd) && \
   cd /mnt && \
   btrfs subvolume create _active && \
   btrfs subvolume create _active/rootvol && \
   btrfs subvolume create _active/homevol && \
   btrfs subvolume create _active/tmp && \
   btrfs subvolume create _snapshots && \
   cd $pth && \
   umount /mnt && \
   mount -o subvol=_active/rootvol /dev/mapper/cryptroot /mnt && \
   mkdir /mnt/home && \
   mkdir /mnt/tmp && \
   mkdir /mnt/boot && \
   mount -o subvol=_active/tmp /dev/mapper/cryptroot /mnt/tmp && \
   mount /dev/$(echo $DISKNAME2)1 /mnt/boot && \
   mount -o subvol=_active/homevol /dev/mapper/cryptroot /mnt/home || \
   return 1
}

generate_fstab ()
{
   mkdir /mnt/etc && \
   echo UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)1) /boot   vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro   0  2 > /mnt/etc/fstab && \
   UUID2=$(blkid -s UUID -o value /dev/mapper/cryptroot) || \
   return 1
   if [ "${SWAP}" != "n" ]; then echo UUID=$(blkid -s UUID -o value /dev/mapper/cryptswap) swap  swap  defaults 0  0 >> /mnt/etc/fstab; fi
   if [ "$(lsblk -d -o name,rota | grep $DISKNAME | grep 1 | wc -l)" -eq 1 ]; then
      echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home/$(echo $USER)/.snapshots btrfs rw,relatime,compress=lzo,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
   else
      echo UUID=$UUID2 /  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=/_active/rootvol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /tmp  btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/tmp  0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_active/homevol   0  0 >> /mnt/etc/fstab
      echo UUID=$UUID2 /home/$(echo $USER)/.snapshots btrfs rw,relatime,compress=lzo,ssd,discard,autodefrag,space_cache,subvol=_snapshots 0  0 >> /mnt/etc/fstab
   fi
}

encryption_key ()
{
   mkdir -m 0700 /mnt/etc/keys && \
   dd if=/dev/urandom bs=1 count=64 of=/mnt/etc/keys/keyfile.bin conv=excl,fsync iflag=fullblock && \
   chmod 600 /mnt/etc/keys/keyfile.bin && \
   echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$ROOTNAME /etc/keys/keyfile.bin && \
   echo "$PASS" | arch-chroot /mnt cryptsetup luksAddKey /dev/$(echo $DISKNAME2)3 /etc/keys/keyfile.bin || \
   return 1
}

enable_network ()
{
   if readlink /sbin/init | grep systemd >/dev/null; then
      arch-chroot /mnt systemctl enable NetworkManager || \
      return 1
   else
      ln -sf /etc/sv/dbus /mnt/etc/runit/runsvdir/default/ && \
      ln -sf /etc/sv/NetworkManager /mnt/etc/runit/runsvdir/default/ || \
      return 1
   fi
}

set_time ()
{
   ln -sf /usr/share/zoneinfo/$(echo $TIME) /mnt/etc/localtime || \
   return 1
}

set_hostname ()
{
   echo $HOST > /mnt/etc/hostname && \
   echo "127.0.0.1   localhost" > /mnt/etc/hosts && \
   echo "::1   localhost" >> /mnt/etc/hosts && \
   echo "127.0.1.1   $(echo $HOST).localdomain  $HOST" >> /mnt/etc/hosts || \
   return 1
}

set_password ()
{
   printf "$PASS\n$PASS\n" | arch-chroot /mnt passwd && \
   printf "$PASS\n$PASS\n" | arch-chroot /mnt passwd $USER || \
   return 1
}

clean_up ()
{
   pacman -Q | awk '{print $1}' > post.txt
   [ "$(diff pre.txt post.txt | wc -l)" -gt 0 ] && pacman -R $(diff pre.txt post.txt | grep ">" | awk '{print $2}') --noconfirm >/dev/null 2>&1
   rm pre.txt post.txt && \
   umount /mnt/boot && \
   umount -A /dev/mapper/cryptroot && \
   cryptsetup close /dev/mapper/cryptroot || \
   return 1
}

check_error ()
{
   if [ $? -ne 0 ]; then
      echo $1
      exit -1
   fi
}

pre_checks

[ -z "$1" ] && wget -O prompts.sh https://raw.github.com/EmperorPenguin18/linux-installer/main/prompts.sh || wget -O prompts.sh "$1"
source ./prompts.sh
user_prompts

echo "-------------------------------------------------"
echo "                Partitioning disk                "
echo "-------------------------------------------------"
setup_partitions
partition_drive
check_error "Partition drive failed"
encrypt_partitions
check_error "Encrypt partitions failed"
echo "-------------------------------------------------"
echo "              Formatting partitions              "
echo "-------------------------------------------------"
format_partitions
check_error "Format partitions failed"
mount_subvolumes
check_error "Mount subvolumes failed"
generate_fstab
check_error "Generate fstab failed"
echo "-------------------------------------------------"
echo "                Installing distro                "
echo "-------------------------------------------------"

wget -O $(echo $DISTRO).sh https://raw.github.com/EmperorPenguin18/linux-installer/main/distros/$(echo $DISTRO).sh
source ./$(echo $DISTRO).sh
print_logo
check_error "Print logo failed"
install_packages
check_error "Install packages failed"
set_locale
check_error "Set locale failed"
encryption_key
check_error "Encryption key failed"
create_user
check_error "Create user failed"
set_initramfs
check_error "Set initramfs failed"
enable_network
check_error "Enable network failed"
create_bootloader
check_error "Create bootloader failed"
distro_clean
check_error "Distro clean failed"

echo "-------------------------------------------------"
echo "                  Finishing up                   "
echo "-------------------------------------------------"
set_time
check_error "Set time failed"
set_hostname
check_error "Set hostname failed"
set_password
check_error "Set password failed"
clean_up
check_error "Clean up failed"
echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"
