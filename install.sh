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
      exit -1
   fi
}

function before_command() {
   case "$BASH_COMMAND" in
      $PROMPT_COMMAND)
	 ;;
      echo)
	 ;;
      printf)
	 ;;
      *)
	 if [ $MANIFEST_MODE = true ]; then # Dry-run mode
            echo $BASH_COMMAND
            return
	 fi
	 if ! command -v $BASH_COMMAND 2>&1 >/dev/null; then
            echo "$BASH_COMMAND isn't available on this system. Please install it before proceeding."
            exit 1
	 else
            echo $BASH_COMMAND
	 fi
	 ;;
   esac
}

function after_command() {
   # Nothing
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
   OPTIND=1
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
}

function pre_checks() {
   trap before_command DEBUG
   PROMPT_COMMAND=after_command
   if [ "$(id -u)" -ne 0 ]; then
      echo "This script must be run as root" 
      exit 1
   fi
   # TODO: will want to check for every needed command before starting
   PROMPT_DISTRO=""
   PROMPT_EFI=""
   PROMPT_SECURE=""
   PROMPT_DISKNAME=""
   PROMPT_FSTYPE=""
   PROMPT_ENCRYPT=""
   PROMPT_PASS=""
   PROMPT_USER=""
   PROMPT_HOST=""
   PROMPT_ARCH=""
   PROMPT_VARIANT=""
   PROMPT_TARGET=""
   if ! ping -q -c 1 -W 1 google.com >/dev/null; then
      echo "The network is down"
      exit 1
   fi
   PROJECT_URL="https://raw.github.com/EmperorPenguin18/linux-installer/main"
}

function prompt_verify() {
   [ -z "${PROMPT_DISTRO}" ] && echo "Distro not set" && exit 1
   [ -z "${PROMPT_EFI}" ] && echo "EFI choice not set" && exit 1
   [ -z "${PROMPT_SECURE}" ] && echo "Secure wipe choice not set" && exit 1
   [ -z "${PROMPT_DISKNAME}" ] && echo "Target diskname not set" && exit 1
   [ -z "${PROMPT_FSTYPE}" ] && echo "Filesystem type not set" && exit 1
   [ -z "${PROMPT_ENCRYPT}" ] && echo "Disk encryption choice not set" && exit 1
   [ -z "${PROMPT_PASS}" ] && echo "Password not set" && exit 1
   [ -z "${PROMPT_USER}" ] && echo "Username not set" && exit 1
   [ -z "${PROMPT_HOST}" ] && echo "Hostname not set" && exit 1
   [ -z "${PROMPT_ARCH}" ] && echo "Target architecture not set" && exit 1
   [ -z "${PROMPT_VARIANT}" ] && echo "Distro variant not set" && exit 1
   [ -z "${PROMPT_TARGET}" ] && echo "Boot target not set" && exit 1
}

function secure_wipe() {
   if [ "$PROMPT_SECURE" = true ]; then
      echo "Doing a secure wipe of disk..."
      cryptsetup open --type plain --key-file /dev/urandom --sector-size 4096 /dev/$PROMPT_DISKNAME && \
      dd if=/dev/zero of=/dev/$PROMPT_DISKNAME status=progress bs=1M
   fi
}

function partition_drive() {
   if [ "${PROMPT_EFI}" = true ]; then
      parted --script /dev/$PROMPT_DISKNAME \
         mklabel gpt \
         mkpart boot fat32 1MB 521MB \
         set 1 esp on \
         mkpart root $PROMPT_FSTYPE 521MB -1s || \
      return 1
   else
      parted --script /dev/$PROMPT_DISKNAME \
         mklabel msdos \
         mkpart primary fat32 1MB 521MB \
         set 1 boot on \
         mkpart primary $PROMPT_FSTYPE 521MB -1s || \
      return 1
   fi
   local partitions=$(awk "!/0 / && /$PROMPT_DISKNAME/ {print \$4}" /proc/partitions)
   BOOTNAME=$(echo $partitions | cut -f 0 -d '\n')
   ROOTNAME=$(echo $partitions | cut -f 1 -d '\n')
}

function encrypt_partitions() {
   if [ "$PROMPT_ENCRYPT" = true ]; then
      echo "$PROMPT_PASS" | cryptsetup -q luksFormat /dev/$ROOTNAME && \
      echo "$PROMPT_PASS" | cryptsetup open /dev/$ROOTNAME $ROOTNAME && \
      ROOTNAME=mapper/$ROOTNAME || \
      return 1
   fi
}

function format_partitions() {
   mkfs.fat -F 32 /dev/$BOOTNAME && \
   mkfs.$PROMPT_FSTYPE /dev/$ROOTNAME || \
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
      btrfs subvolume set-default $(btrfs subvolume list -p /tmp/mnt | awk '/@root/ {print $2}') / && \
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
   mkdir -p /tmp/mnt/etc || \
   return 1
   for I in $(grep "/tmp/mnt" /proc/self/mountinfo); do
      echo $I | awk '{print $10 $5 $9 $11}' >> /tmp/mnt/etc/fstab || \
      return 1
   done
}

function print_logo() {
   local screenfetch=$(curl -s "https://git.io/vaHfR") && \
   echo $screenfetch | sh -s -- -D "${PROMPT_DISTRO}" -L || \
   return 1
   #echo $screenfetch | sh -s -- -D "${PROMPT_DISTRO}"-linux -L
}

function create_user() {
   useradd -R /tmp/mnt -m -G video $PROMPT_USER || \
   return 1
}

function set_hostname () {
   echo $PROMPT_HOST > /tmp/mnt/etc/hostname || \
   return 1
}

function set_password() {
   printf "$PROMPT_PASS\n$PROMPT_PASS\n" | passwd -R /tmp/mnt && \
   printf "$PROMPT_PASS\n$PROMPT_PASS\n" | passwd -R /tmp/mnt $USER || \
   return 1
}

function clean_up() {
   umount -R /tmp/mnt || \
   return 1
   if [ "$PROMPT_ENCRYPT" = true ]; then
      cryptsetup close /dev/$ROOTNAME || \
      return 1
   fi
}

######################################################################
################ Distro-specific functions (Arch) ####################
######################################################################

function install_packages() {
   local file="/tmp/mnt/$PROMPT_DISTRO.qcow2" && \
   curl -s "https://jenkins.linuxcontainers.org/job/image-$PROMPT_DISTRO/architecture=$PROMPT_ARCH,release=current,variant=$PROMPT_VARIANT/lastSuccessfulBuild/artifact/disk.qcow2" > "$file" && \
   virt-copy-out -a "$file" /tmp/mnt && \
   rm -f "$file" || \
   return 1
}

function create_bootloader() {
   echo "GRUB_ENABLE_CRYPTODISK=y" >> /tmp/mnt/etc/default/grub && \
   grub-install -d /tmp/mnt/usr/lib/grub --boot-directory=/tmp/mnt/boot --target=$PROMPT_TARGET --bootloader-id=GRUB /dev/$PROMPT_DISKNAME --recheck --removable && \
   grub-mkconfig -o /tmp/mnt/boot/grub/grub.cfg || \
   return 1
   #arch-chroot /mnt dracut --force --regenerate-all || \
}

function distro_clean() {
   # Nothing
}

######################################################################
#################### Actual script begins ############################
######################################################################

echo "-------------------------------------------------"
echo "               Initializing script               "
echo "-------------------------------------------------"
parse_args
pre_checks
[ -z "${PROMPT_FILE}" ] && \
curl -sL $PROJECT_URL/prompts.sh | . /dev/stdin || \
. $PROMPT_FILE
user_prompts
prompt_verify

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
print_logo $PROMPT_DISTRO
check_error "Print logo failed"
DISTRO_SCRIPT=$(curl -sL $PROJECT_URL/distros/$PROMPT_DISTRO.sh)
[ -z "${DISTRO_SCRIPT}" ] && echo "Unsupported distro requested" && exit 1 || \
echo $DISTRO_SCRIPT | . /dev/stdin
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
create_user
check_error "Create user failed"
set_hostname
check_error "Set hostname failed"
set_password
check_error "Set password failed"
clean_up
check_error "Clean up failed"
echo "-------------------------------------------------"
echo "          All done! You can reboot now.          "
echo "-------------------------------------------------"
