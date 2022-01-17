#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE
#!/bin/sh

print_logo ()
{
  WHITE='\033[1;37m'
  GREEN='\033[1;32m'
  NC='\033[0m'
  printf "           ${WHITE}.;ldkO0000Okdl;.
       .;d00xl:^''''''^:ok00d;.
     .d00l'                'o00d.
   .d0Kd'  ${GREEN}Okxol:;,.          ${WHITE}:O0d.
  .OK${GREEN}KKK0kOKKKKKKKKKKOxo:,      ${WHITE}lKO.
 ,0K${GREEN}KKKKKKKKKKKKKKK0P^${WHITE},,,${GREEN}^dx:    ${WHITE};00,
.OK${GREEN}KKKKKKKKKKKKKKKk'${WHITE}.oOPPb.${GREEN}'0k.   ${WHITE}cKO.
:KK${GREEN}KKKKKKKKKKKKKKK: ${WHITE}kKx..dd ${GREEN}lKd   ${WHITE}'OK:
dKK${GREEN}KKKKKKKKKOx0KKKd ${WHITE}^0KKKO' ${GREEN}kKKc   ${WHITE}dKd
dKK${GREEN}KKKKKKKKKK;.;oOKx,..${WHITE}^${GREEN}..;kKKK0.  ${WHITE}dKd
:KK${GREEN}KKKKKKKKKK0o;...^cdxxOK0O/^^'  ${WHITE}.0K:
 kKK${GREEN}KKKKKKKKKKKKK0x;,,......,;od  ${WHITE}lKk
 '0K${GREEN}KKKKKKKKKKKKKKKKKKKK00KKOo^  ${WHITE}c00'
  'kK${GREEN}KKOxddxkOO00000Okxoc;''   ${WHITE}.dKk'
    l0Ko.                    .c00l'
     'l0Kk:.              .;xK0l'
        'lkK0xl:;,,,,;:ldO0kl'
            '^:ldxkkkkxdl:^'${NC}\n" || \
  return 1
}

install_packages ()
{
  VIRTUAL=$(dmidecode -s system-product-name)
  if [ "$(cat /proc/cpuinfo | grep name | grep Intel | wc -l)" -gt 0 ]; then
    CPU="intel iucode-tool"
  else
    CPU="amd"
  fi
  if [ "${VIRTUAL}" = "VirtualBox" ]; then
    VIRTUAL="virtualbox-guest-x11 virtualbox-guest-tools"
  elif [ "${VIRTUAL}" = "KVM" ]; then
    VIRTUAL="qemu-guest-agent"
  else
    VIRTUAL=""
  fi
  if [ "${BOOTTYPE}" = "efi" ]; then
    GRUB="grub2-x86_64-efi efibootmgr"
  else
    GRUB="grub2"
  fi
  [ -f /etc/yum.repos.d/fedora.repo ] && mv /etc/yum.repos.d/fedora.repo /etc/yum.repos.d/fedora.repo.bak
  NUM=$(curl -sL https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/ | cut -d '>' -f 2 | cut -d '/' -f 1 | sed '1,4d' | head -n -3 | sort -g | tail -1) && \
  pacman -S dnf expect --noconfirm --needed && \
  mkdir -p /etc/yum.repos.d && \
  printf '[fedora]\nname=Fedora $releasever - $basearch\n#baseurl=http://download.example/pub/fedora/linux/releases/$releasver/Everything/$basearch/os\nmetalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch\nenabled=1\ncountme=1\nmetadata_expire=7d\nrepo_gpgcheck=0\ntype=rpm\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch\nskip_if_unavailable=False' > /etc/yum.repos.d/fedora.repo && \
  dnf install -y --installroot=/mnt --releasever=$NUM --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck zypper && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/tumbleweed/repo/oss/ oss && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/tumbleweed/repo/non-oss/ non-oss && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/update/tumbleweed/ update && \
  arch-chroot /mnt zypper -n --gpg-auto-import-keys in --replacefiles --allow-vendor-change filesystem coreutils gawk kernel-default busybox-adduser glibc-locale $GRUB os-prober ucode-$CPU btrfsprogs dosfstools cryptsetup sudo NetworkManager fish $VIRTUAL && \
  arch-chroot /mnt zypper -n ar -f https://download.opensuse.org/repositories/openSUSE:Factory/standard/ factory && \
  printf '#!/bin/sh
arch-chroot /mnt zypper in --replacefiles --allow-vendor-change rpm-config-SUSE rpm libsolv-tools libzypp zypper > /dev/null' > temp.sh && \
  chmod +x temp.sh && \
  printf '#!/bin/expect -f
set timeout 25
spawn ./temp.sh
expect "filler"
send -- "3\r"
expect "filler2"
send -- "3\r"
expect "filler3"
send -- "\r"
set timeout 100
expect "filler4"
send -- "r\r"
expect eof' > script.exp && \
  chmod +x script.exp && \
  ./script.exp && \
  rm temp.sh script.exp && \
  arch-chroot /mnt zypper -n rr factory || \
  return 1
  [ -f /etc/yum.repos.d/fedora.repo.bak ] && mv /etc/yum.repos.d/fedora.repo.bak /etc/yum.repos.d/fedora.repo
  return 0
}

set_locale ()
{
  sed -i '$s|^|PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin |' /usr/bin/arch-chroot && \
  arch-chroot /mnt zypper -n aloc en_US || \
  return 1
}

create_user ()
{
  printf "$PASS\n$PASS\n" | arch-chroot /mnt adduser -s /bin/fish -G wheel $USER && \
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
  echo "SUSE_BTRFS_SNAPSHOT_BOOTING=true" >> /mnt/etc/default/grub && \
  echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub && \
  echo "GRUB_CMDLINE_LINUX=\"cryptkey=rootfs:/etc/keys/keyfile.bin cryptdevice=UUID=$(blkid -s UUID -o value /dev/$ROOTNAME):cryptroot resume=/dev/mapper/cryptswap root=UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot) rootflags=subvol=/_active/rootvol rw\"" >> /mnt/etc/default/grub || \
  return 1
  if [ "${BOOTTYPE}" = "efi" ]; then
    arch-chroot /mnt grub2-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck || \
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
