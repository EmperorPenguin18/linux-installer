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
 ,0K${GREEN}KKKKKKKKKKKKKKK0P^${WHITE},,,^dx:    ${WHITE};00,
.OK${GREEN}KKKKKKKKKKKKKKKk'${WHITE}.oOPPb.'0k.   ${WHITE}cKO.
:KK${GREEN}KKKKKKKKKKKKKKK: ${WHITE}kKx..dd lKd   ${WHITE}'OK:
dKK${GREEN}KKKKKKKKKOx0KKKd ${WHITE}^0KKKO' kKKc   ${WHITE}dKd
dKK${GREEN}KKKKKKKKKK;.;oOKx,..${WHITE}^..;kKKK0.  ${WHITE}dKd
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
