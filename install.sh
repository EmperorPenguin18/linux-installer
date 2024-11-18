#!/bin/sh

#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE

######################################################################
######################### Library functions ##########################
######################################################################

function check_error() {
   if [ $? -ne 0 ]; then
      echo $1
      clean_up
      exit -1
   fi
}

function before_command() {
   case "$BASH_COMMAND" in
      $PROMPT_COMMAND)
	 ;;
      echo*)
	 ;;
      printf*)
	 ;;
      *)
	 if [ $MANIFEST_MODE = true ]; then # Dry-run mode
            echo "Not implemented yet"
	    exit 1
	 fi
         #echo "$BASH_COMMAND" somethings wrong
	 ;;
   esac
}

function after_command() {
   true # Nothing
}

#function arch-chroot() {
   #TODO
   # Mimic arch-chroot
   # sbin thing
   # qemu-static
#}

######################################################################
######################## Common functions ############################
######################################################################

function parse_args() {
   local saved_args="$@"
   OPTIND=1
   set -- $saved_args
   MANIFEST_MODE=false
   while getopts "h?m:" opt; do
      case "$opt" in
         h|\?)
            echo "This is a help message"
            exit 0
            ;;
         m)  MANIFEST_MODE=true
            ;;
      esac
   done
   shift $((OPTIND-1))
   [ "${1:-}" = "--" ] && shift
   PROMPT_FILE="$1"
   return 0
}

function pre_checks() {
   trap before_command DEBUG
   PROMPT_COMMAND=after_command
   set -T # trap inherit
   [ "$(id -u)" -ne 0 ] && echo "This script must be run as root" && exit 1
   # TODO: will want to check for every needed command before starting
   command -v "qemu-img" || return 1
   PROMPT_DISTRO=""
   PROMPT_EFI=""
   PROMPT_SECURE=""
   PROMPT_DISKNAME=""
   PROMPT_FSTYPE=""
   PROMPT_ENCRYPT=""
   PROMPT_PASS=""
   PROMPT_HOST=""
   PROMPT_ARCH=""
   PROMPT_RELEASE=""
   PROMPT_VARIANT=""
   if ! ping -q -c 1 -W 1 google.com >/dev/null; then
      echo "The network is down"
      exit 1
   fi
   PROJECT_URL="https://raw.github.com/EmperorPenguin18/linux-installer/main"
   return 0
}

function prompt_verify() {
   [ -z "${PROMPT_DISTRO}" ] && echo "Distro not set" && return 1
   [ -z "${PROMPT_EFI}" ] && echo "EFI choice not set" && return 1
   [ -z "${PROMPT_SECURE}" ] && echo "Secure wipe choice not set" && return 1
   [ -z "${PROMPT_DISKNAME}" ] && echo "Target diskname not set" && return 1
   [ -z "${PROMPT_FSTYPE}" ] && echo "Filesystem type not set" && return 1
   [ -z "${PROMPT_ENCRYPT}" ] && echo "Disk encryption choice not set" && return 1
   [ -z "${PROMPT_PASS}" ] && echo "Password not set" && return 1
   [ -z "${PROMPT_HOST}" ] && echo "Hostname not set" && return 1
   [ -z "${PROMPT_ARCH}" ] && echo "Target architecture not set" && return 1
   [ -z "${PROMPT_RELEASE}" ] && echo "Distro release not set" && return 1
   [ -z "${PROMPT_VARIANT}" ] && echo "Distro variant not set" && return 1
   return 0
}

function secure_wipe() {
   if [ "$PROMPT_SECURE" = true ]; then
      echo "Doing a secure wipe of disk..." && \
      dd if=/dev/zero of=/dev/$PROMPT_DISKNAME status=progress bs=1M
   fi
   return 0
}

function partition_drive() {
   if [ "${PROMPT_EFI}" = true ]; then
      parted --script /dev/$PROMPT_DISKNAME -- \
         mklabel gpt \
         mkpart boot fat32 1MB 521MB \
         set 1 esp on \
         mkpart root $PROMPT_FSTYPE 521MB 100% || \
      return 1
   else
      parted --script /dev/$PROMPT_DISKNAME -- \
         mklabel msdos \
         mkpart primary fat32 1MB 521MB \
         set 1 boot on \
         mkpart primary $PROMPT_FSTYPE 521MB -1s || \
      return 1
   fi
   local partitions=$(awk "!/0 / && /$PROMPT_DISKNAME/ {print \$4}" /proc/partitions) && \
   BOOTNAME=$(echo $partitions | cut -f 1 -d ' ') && \
   ROOTNAME=$(echo $partitions | cut -f 2 -d ' ') || \
   return 1
}

function encrypt_partitions() {
   if [ "$PROMPT_ENCRYPT" = true ]; then
      echo "$PROMPT_PASS" | cryptsetup -q luksFormat --type luks1 /dev/$ROOTNAME && \
      echo "$PROMPT_PASS" | cryptsetup open /dev/$ROOTNAME $ROOTNAME && \
      ROOTNAME=mapper/$ROOTNAME || \
      return 1
   fi
}

function format_partitions() {
   local opt=-F
   if [ "$PROMPT_FSTYPE" = "btrfs" ]; then
      opt=-f
   fi
   mkfs.fat -F 32 /dev/$BOOTNAME && \
   mkfs.$PROMPT_FSTYPE $opt -q /dev/$ROOTNAME || \
   return 1
}

function mount_subvolumes() {
   mkdir -p /tmp/mnt && \
   mount -o defaults /dev/$ROOTNAME /tmp/mnt || \
   return 1
   if [ "$PROMPT_FSTYPE" = "btrfs" ]; then
      local opts="defaults,compress=lzo" && \
      btrfs subvolume create /tmp/mnt/@root && \
      btrfs subvolume create /tmp/mnt/@home && \
      btrfs subvolume create /tmp/mnt/@snapshots && \
      btrfs subvolume create /tmp/mnt/@var_log && \
      btrfs subvolume set-default $(btrfs subvolume list -p /tmp/mnt | awk '/@root/ {print $2}') /tmp/mnt && \
      umount /tmp/mnt && \
      mount -o $opts /dev/$ROOTNAME /tmp/mnt && \
      mkdir -p /tmp/mnt/home && \
      mount -o $opts,subvol=@home /dev/$ROOTNAME /tmp/mnt/home && \
      mkdir -p /tmp/mnt/var/log && \
      mount -o $opts,subvol=@var_log /dev/$ROOTNAME /tmp/mnt/var/log || \
      return 1
   fi
   mkdir -p /tmp/mnt/boot && \
   mount -o defaults /dev/$BOOTNAME /tmp/mnt/boot || \
   return 1
}

function generate_fstab() {
   mkdir -p /tmp/mnt/etc && \
   awk '/\/tmp\/mnt/ {print $10 " " $5 " " $9 " " $11}' /proc/self/mountinfo | sed 's|tmp/mnt/||g;s|tmp/mnt||g' > /tmp/mnt/etc/fstab || \
   return 1
}

function print_logo() {
   local screenfetch="$(curl -sL "https://git.io/vaHfR")" && \
   echo "$screenfetch" | sh -s -- -D "${PROMPT_DISTRO}" -L 2>/dev/null || \
   return 1
}

function set_hostname () {
   echo $PROMPT_HOST > /tmp/mnt/etc/hostname || \
   return 1
}

function set_password() {
   usermod -R /tmp/mnt --password $(echo "$PROMPT_PASS" | openssl passwd -1 -stdin) root || \
   return 1
}

function clean_up() {
   umount -R /tmp/mnt 2>/dev/null
   if [ "$PROMPT_ENCRYPT" = true ]; then
      cryptsetup close /dev/$ROOTNAME 2>/dev/null
   fi
}

######################################################################
################ Distro-specific functions (Arch) ####################
######################################################################

function install_packages() {
   local file="/tmp/mnt/$PROMPT_DISTRO" && \
   local url="https://jenkins.linuxcontainers.org/job/image-$PROMPT_DISTRO/architecture=$PROMPT_ARCH,release=$PROMPT_RELEASE,variant=$PROMPT_VARIANT/lastSuccessfulBuild/artifact" && \
   local arch="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" && \
   curl -s "$url/disk.qcow2" > "$file.qcow2" && \
   qemu-img convert -O raw "$file.qcow2" "$file.img" && \
   mkdir -p /tmp/root
   if mount -o offset=105906176 "$file.img" /tmp/root; then
      rsync -a --exclude='boot' /tmp/root/ /tmp/mnt >/dev/null && \
      rsync -aL /tmp/root/boot/ /tmp/mnt/boot >/dev/null && \
      umount /tmp/root && \
      rm -f "$file.qcow2" "$file.img" || \
      return 1
   elif [ "$PROMPT_ARCH" = "$arch" ]; then
      curl -s "$url/rootfs.tar.xz" > "$file.tar.xz" && \
      tar -xf "$file.tar.xz" -C /tmp/mnt && \
      cp $(find / -name "vmlinuz-linux*") $(find / -name "*linux.img") /tmp/mnt/boot/ && \
      rm -f "$file.tar.xz" || \
      return 1
   else
      echo "The combination of $PROMPT_DISTRO+$PROMPT_ARCH+$PROMPT_VARIANT is unsupported." && \
      return 1
   fi
}

function create_bootloader() {
   local target=""
   local efi=""
   local dir=""
   if [ "$PROMPT_ARCH" = "amd64" -a "$PROMPT_EFI" = false ]; then
       target="i386-pc"
   elif [ "$PROMPT_ARCH" = "amd64" -a "$PROMPT_EFI" = true ]; then
       target="x86_64-efi"
       efi=--efi-directory=/tmp/mnt/boot
   elif [ "$PROMPT_ARCH" = "arm64" -a "$PROMPT_EFI" = false ]; then
       target="arm-uboot"
   elif [ "$PROMPT_ARCH" = "arm64" -a "$PROMPT_EFI" = true ]; then
       target="arm64-efi"
       efi=--efi-directory=/tmp/mnt/boot
   elif [ "$PROMPT_ARCH" = "armhf" -a "$PROMPT_EFI" = false ]; then
       target="arm-uboot"
   elif [ "$PROMPT_ARCH" = "armhf" -a "$PROMPT_EFI" = true ]; then
       target="arm-efi"
       efi=--efi-directory=/tmp/mnt/boot
   fi
   local arch="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
   if [ "$PROMPT_ARCH" != "$arch" ]; then
       dir=--directory=/tmp/mnt/usr/lib/grub/$target
   fi
   grub-install --target=$target $dir $efi --boot-directory=/tmp/mnt/boot --bootloader-id=GRUB /dev/$PROMPT_DISKNAME --recheck --removable && \
   local grub_cfg="/tmp/mnt/boot/grub/grub.cfg" && \
   printf "set default=0\nset timeout=5\nmenuentry '$PROMPT_DISTRO' {
           set root=(hd0,1)
	   $([ "$PROMPT_ENCRYPT" = true ] && printf "insmod luks
	   cryptomount (hd0,2)")
           linux /$(find /tmp/mnt/boot -name "vmlinuz*" -printf "%f\n" | tail -1) root=/dev/$ROOTNAME ro
           initrd /$(find /tmp/mnt/boot -name "init*" -printf "%f\n" | tail -1)\n}
" > $grub_cfg || \
   return 1
}

function distro_clean() {
   true # Nothing
}

######################################################################
#################### Actual script begins ############################
######################################################################

echo "-------------------------------------------------"
echo "               Initializing script               "
echo "-------------------------------------------------"
parse_args "$@"
check_error "Parsing cmd-line arguments failed"
pre_checks
check_error "System checks failed"
[ -z "${PROMPT_FILE}" ] && \
eval "$(curl -sL $PROJECT_URL/prompts.sh)" || \
eval "$(cat $PROMPT_FILE)" || \
exit 1
user_prompts
check_error "User prompt script failed"
prompt_verify
check_error "Failed to verify prompt inputs"

echo "-------------------------------------------------"
echo "                Partitioning disk                "
echo "-------------------------------------------------"
secure_wipe
check_error "Secure wipe failed"
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

echo "-------------------------------------------------"
echo "                Installing distro                "
echo "-------------------------------------------------"
print_logo
check_error "Print logo failed"
DISTRO_SCRIPT=$(curl -sL $PROJECT_URL/distros/$PROMPT_DISTRO.sh)
[ -z "${DISTRO_SCRIPT}" ] && echo "Unsupported distro requested" && exit 1 || \
eval "$DISTRO_SCRIPT"
install_packages
check_error "Install packages failed"
generate_fstab
check_error "Generate fstab failed"
create_bootloader
check_error "Create bootloader failed"
distro_clean
check_error "Distro clean failed"

echo "-------------------------------------------------"
echo "                  Finishing up                   "
echo "-------------------------------------------------"
set_hostname
check_error "Set hostname failed"
set_password
check_error "Set password failed"
clean_up
check_error "Clean up failed"
echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"
