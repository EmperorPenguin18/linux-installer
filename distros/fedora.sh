#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

print_logo ()
{
   PURPLE='\033[1;34m'
   WHITE='\033[1;37m'
   NC='\033[0m'
   printf "          ${PURPLE}/:-------------:\
       ${PURPLE}:-------------------::
     ${PURPLE}:-----------${WHITE}/shhOHbmp${PURPLE}---:\
   ${PURPLE}/-----------${WHITE}omMMMNNNMMD${PURPLE}  ---:
  ${PURPLE}:-----------${WHITE}sMMMMNMNMP${PURPLE}.    ---:
 ${PURPLE}:-----------${WHITE}:MMMdP${PURPLE}-------    ---\
${PURPLE},------------${WHITE}:MMMd${PURPLE}--------    ---:
${PURPLE}:------------${WHITE}:MMMd${PURPLE}-------    .---:
${PURPLE}:----    ${WHITE}oNMMMMMMMMMNho${PURPLE}     .----:
${PURPLE}:--     .${WHITE}+shhhMMMmhhy++${PURPLE}   .------/
${PURPLE}:-    -------${WHITE}:MMMd${PURPLE}--------------:
${PURPLE}:-   --------${WHITE}/MMMd${PURPLE}-------------;
${PURPLE}:-    ------${WHITE}/hMMMy${PURPLE}------------:
${PURPLE}:-- ${WHITE}:dMNdhhdNMMNo${PURPLE}------------;
${PURPLE}:---${WHITE}:sdNMMMMNds:${PURPLE}------------:
${PURPLE}:------${WHITE}:://:${PURPLE}-------------::
${PURPLE}:---------------------://${NC}\n" || \
   return 1
}

set_locale ()
{
   arch-chroot /mnt localedef -c -i en_US -f UTF-8 en_US-UTF-8 || \
   return 1
}

install_packages ()
{
   if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then CPU="iucode-tool"; fi
   if [ "${VIRTUAL}" = "KVM" ]; then
      VIRTUAL="qemu-guest-agent"
   else
      VIRTUAL=""
   fi
   if [ "${BOOTTYPE}" = "efi" ]; then
      GRUB="grub2-efi-x64 grub2-efi-x64-modules shim-x64 efibootmgr"
   else
      GRUB="grub2-pc"
   fi
   [ -f /etc/yum.repos.d/fedora.repo ] && mv /etc/yum.repos.d/fedora.repo /etc/yum.repos.d/fedora.repo.bak
   NUM=$(curl -sL https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/ | cut -d '>' -f 2 | cut -d '/' -f 1 | sed '1,4d' | head -n -3 | sort -g | tail -1) && \
   pacman -S dnf --noconfirm --needed && \
   mkdir -p /etc/yum.repos.d && \
   printf '[fedora]\nname=Fedora $releasever - $basearch\n#baseurl=http://download.example/pub/fedora/linux/releases/$releasver/Everything/$basearch/os\nmetalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch\nenabled=1\ncountme=1\nmetadata_expire=7d\nrepo_gpgcheck=0\ntype=rpm\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch\nskip_if_unavailable=False' > /etc/yum.repos.d/fedora.repo && \
   dnf install -y --installroot=/mnt --releasever=$NUM --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck basesystem dnf glibc-langpack-en glibc-locale-source iputils NetworkManager && \
   sed -i 's|SHELL|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin SHELL|g' /usr/bin/arch-chroot && \
   set_locale && \
   arch-chroot /mnt dnf install -y --setopt=install_weak_deps=False --setopt=keepcache=True kernel os-prober $GRUB passwd linux-firmware btrfs-progs dosfstools $CPU microcode_ctl git $VIRTUAL cryptsetup sudo fish || \
   return 1
   [ -f /etc/yum.repos.d/fedora.repo.bak ] && mv /etc/yum.repos.d/fedora.repo.bak /etc/yum.repos.d/fedora.repo
   return 0
}

create_user ()
{
   arch-chroot /mnt useradd -m -s /bin/fish -G wheel $USER && \
   echo "root ALL=(ALL) ALL" > /mnt/etc/sudoers && \
   echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers || \
   return 1
}

set_initramfs ()
{
   echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$ROOTNAME) /etc/keys/keyfile.bin luks,discard,key-slot=1" > /mnt/etc/crypttab
   [ "${SWAP}" != "n" ] && echo "cryptswap UUID=$(blkid -s UUID -o value /dev/$(echo $DISKNAME2)3) /etc/keys/keyfile.bin luks,swap,key-slot=1" >> /mnt/etc/crypttab
   echo 'install_items+=" /etc/keys/keyfile.bin /etc/crypttab "' > /mnt/etc/dracut.conf.d/10-crypt.conf || \
   return 1
}

create_bootloader ()
{
   echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub && \
   echo "GRUB_CMDLINE_LINUX=\"cryptkey=rootfs:/etc/keys/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot resume=/dev/mapper/cryptswap root=UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot) rootflags=subvol=/_active/rootvol rw\"" >> /mnt/etc/default/grub || \
   return 1
   if [ "${BOOTTYPE}" = "efi" ]; then
      arch-chroot /mnt dnf reinstall -y grub2* shim* && \
      mv /mnt/boot/EFI/EFI/* /mnt/boot/EFI/ && \
      rmdir /mnt/boot/EFI/EFI && \
      arch-chroot /mnt grub2-mkconfig -o /boot/EFI/fedora/grub.cfg || \
      return 1
   else
      arch-chroot /mnt grub2-install /dev/$DISKNAME || \
      return 1
   fi
   arch-chroot /mnt grub2-mkconfig -o /boot/grub2/grub.cfg && \
   arch-chroot /mnt dracut --force --regenerate-all || \
   return 1
}

distro_clean ()
{
   return 0
}
