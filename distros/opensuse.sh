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

install_git ()
{
    PWD=$(pwd)
    if [ ! -d "/mnt/home/build" ]
    then
      mkdir /mnt/home/build && \
      chgrp nobody /mnt/home/build && \
      chmod g+ws /mnt/home/build && \
      setfacl -m u::rwx,g::rwx /mnt/home/build && \
      setfacl -d --set u::rwx,g::rwx,o::- /mnt/home/build || \
      return 1
    fi
    cd /mnt/home/build
    for I in $@
    do
        git clone https://aur.archlinux.org/$I.git newgitpackage && \
        cd newgitpackage && \
        sudo -u nobody makepkg --noconfirm && \
        pacman -U *.pkg* --noconfirm --needed && \
        cd ../ && \
        rm -r newgitpackage || \
        return 1
    done
    cd $PWD
    return 0
}

install_packages ()
{
  pacman -S git fakeroot binutils meson ninja --noconfirm --needed --asdeps && \
  install_git zchunk && \
  pacman -R meson ninja --noconfirm && \
  pacman -S rpm-tools cmake ruby swig --noconfirm --needed --asdeps && \
  install_git libsolv && \
  pacman -R ruby swig --noconfirm && \
  pacman -S libsigc++ yaml-cpp asciidoc boost dejagnu doxygen graphviz ninja protobuf --noconfirm --needed --asdeps && \
  install_git libzypp && \
  pacman -R dejagnu doxygen graphviz protobuf --noconfirm && \
  pacman -S augeas asciidoctor --noconfirm --needed --asdeps && \
  install_git zypper && \
  zypper --root /mnt in vi || \
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
