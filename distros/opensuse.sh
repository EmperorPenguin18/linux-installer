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
  pacman -S rpm-tools libsigc++ yaml-cpp augeas --noconfirm --needed --asdeps && \
  URL="https://mirror.csclub.uwaterloo.ca/opensuse/distribution/openSUSE-current/repo/oss/x86_64/" && \
  PKGS="$(curl -s "$URL" | cut -d '"' -f 2)" && \
  wget -q "$URL$(echo "$PKGS" | grep -E "zchunk-[0-9]")" && \
  rpm -i zchunk* --nodeps && \
  rm zchunk* && \
  wget -q "$URL$(echo "$PKGS" | grep -E "libsolv-tools-[0-9]")" && \
  rpm -i libsolv* --nodeps && \
  rm libsolv* && \
  wget -q "$URL$(echo "$PKGS" | grep -E "libzypp-[0-9]")" && \
  rpm -i libzypp* --nodeps && \
  rm libzypp* && \
  wget -q "$URL$(echo "$PKGS" | grep -E "zypper-[0-9]")" && \
  rpm -i zypper* --nodeps && \
  rm zypper* && \
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
