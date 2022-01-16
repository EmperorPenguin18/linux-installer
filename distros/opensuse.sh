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
  NUM=$(curl -sL https://mirror.csclub.uwaterloo.ca/pub/fedora/linux/releases/ | cut -d '>' -f 2 | cut -d '/' -f 1 | sed '1,4d' | head -n -3 | sort -g | tail -1) && \
  pacman -S dnf --noconfirm --needed && \
  mkdir /etc/yum.repos.d && \
  printf '[fedora]\nname=Fedora $releasever - $basearch\n#baseurl=http://download.example/pub/fedora/linux/releases/$releasver/Everything/$basearch/os\nmetalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch\nenabled=1\ncountme=1\nmetadata_expire=7d\nrepo_gpgcheck=0\ntype=rpm\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch\nskip_if_unavailable=False' > /etc/yum.repos.d/fedora.repo && \
  dnf install -y --installroot=/mnt --releasever=$NUM --setopt=install_weak_deps=False --setopt=keepcache=True --nogpgcheck zypper && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/tumbleweed/repo/oss/ oss && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/tumbleweed/repo/non-oss/ non-oss && \
  arch-chroot /mnt zypper -n ar -f http://download.opensuse.org/update/tumbleweed/ update && \
  arch-chroot /mnt zypper -n --gpg-auto-import-keys in --replacefiles patterns-base-basesystem kernel-default glibc-locale-base $GRUB os-prober ucode-$CPU btrfsprogs dosfstools sudo NetworkManager fish $VIRTUAL || \
  return 1
}

set_locale ()
{
  return 0
}

create_user ()
{
  return 0
}

set_initramfs ()
{
  return 0
}

create_bootloader ()
{
  return 0
}

distro_clean ()
{
  return 0
}
