#!/bin/sh

#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE

function user_prompts() {
   local width=80
   local height=30
   ###
   PROMPT_DISTRO=$(whiptail --backtitle "Triumph Installer" --title "Target options" --radiolist "Choose which distro to install" $height $width 6 "Arch Linux" "Uses pacman" ON "Debian" "Uses apt" OFF "Fedora" "Uses dnf" OFF "Gentoo" "Uses portage" OFF "openSUSE" "Uses zypper" OFF "Void Linux" "Uses xbps" OFF 3>&1 1>&2 2>&3 | sed 's/ //g' | awk '{print tolower($0)}')
   ###
   local args=()
   if [ "$PROMPT_DISTRO" = "archlinux" -o "$PROMPT_DISTRO" = "debian" -o "$PROMPT_DISTRO" = "fedora" -o "$PROMPT_DISTRO" = "gentoo" -o "$PROMPT_DISTRO" = "opensuse" -o "$PROMPT_DISTRO" = "voidlinux" ]; then
      args+=(amd64 "(x86_64, AMD, Intel)" ON)
   fi
   if [ "$PROMPT_DISTRO" = "archlinux" -o "$PROMPT_DISTRO" = "debian" -o "$PROMPT_DISTRO" = "fedora" -o "$PROMPT_DISTRO" = "gentoo" -o "$PROMPT_DISTRO" = "opensuse" -o "$PROMPT_DISTRO" = "voidlinux" ]; then
      args+=(arm64 "(aarch64, Qualcomm, Apple)" OFF)
   fi
   if [ "$PROMPT_DISTRO" = "debian" -o "$PROMPT_DISTRO" = "rpi" ]; then
      args+=(armhf "(Arm 32-bit, Broadcom)" OFF)
   fi
   PROMPT_ARCH=$(whiptail --backtitle "Triumph Installer" --title "Target options" --radiolist "What architecture are you installing to? It can be different than what you are installing from." $height $width $((${#args[@]}/3)) "${args[@]}" 3>&1 1>&2 2>&3)
   ###
   PROMPT_RELEASE=current
   if [ "$PROMPT_DISTRO" = "debian" ]; then
      PROMPT_RELEASE=bookworm
   elif [ "$PROMPT_DISTRO" = "fedora" ]; then
      PROMPT_RELEASE=41
   elif [ "$PROMPT_DISTRO" = "opensuse" ]; then
      PROMPT_RELEASE=tumbleweed
   fi
   ###
   PROMPT_VARIANT=default
   if [ "$PROMPT_DISTRO" = "gentoo" ]; then
      #PROMPT_VARIANT=$(whiptail --backtitle "Triumph Installer" --title "Target options" --radiolist "This distro has variants. Which one do you want?" $height $width 2 "systemd" "" ON "openrc" "" OFF 3>&1 1>&2 2>&3)
      PROMPT_VARIANT="openrc"
   elif [ "$PROMPT_DISTRO" = "voidlinux" ]; then
      PROMPT_VARIANT=$(whiptail --backtitle "Triumph Installer" --title "Target options" --radiolist "This distro has variants. Which one do you want?" $height $width 2 "default" "(glibc)" ON "musl" "" OFF 3>&1 1>&2 2>&3)
   fi
   ###
   local disk_opts="$(lsblk | awk '!/─/ {if (NR!=1) {print $1 " " $4 " OFF"}}')"
   local disk_count="$(echo "$disk_opts" | wc -l)"
   PROMPT_DISKNAME=$(whiptail --backtitle "Triumph Installer" --title "Hardware info" --radiolist "Which disk do you want to install to?" $height $width $disk_count $disk_opts 3>&1 1>&2 2>&3)
   ###
   if whiptail --backtitle "Triumph Installer" --title "Hardware info" --yesno "Does your system support EFI?" $height $width; then
      PROMPT_EFI=true
   else
      PROMPT_EFI=false
   fi
   ###
   if whiptail --backtitle "Triumph Installer" --title "Hardware info" --yesno "Do you want to enable disk encryption?" $height $width; then
      PROMPT_ENCRYPT=true
   else
      PROMPT_ENCRYPT=false
   fi
   ###
   args=()
   for I in $(find /usr/bin/ -name "mkfs.*" | cut -f2 -d'.'); do
      args+=($I "" OFF)
   done
   PROMPT_FSTYPE=$(whiptail --backtitle "Triumph Installer" --title "User configs" --radiolist "What file system do you want your root partition to be? If you're not sure, then pick ext4. Note that if you choose btrfs, then subvolumes will be set up automatically." $height $width $((${#args[@]}/3)) "${args[@]}" 3>&1 1>&2 2>&3)
   ###
   PROMPT_HOST="$(whiptail --backtitle "Triumph Installer" --title "User configs" --inputbox "Enter your system host name:" $height $width 3>&1 1>&2 2>&3)"
   ###
   PROMPT_PASS="$(whiptail --backtitle "Triumph Installer" --title "User configs" --passwordbox "Enter your password:" $height $width 3>&1 1>&2 2>&3)"
   ###
   if whiptail --backtitle "Triumph Installer" --title "Security" --yesno "Do you want to securely wipe your disk before installing? (Takes a while)" $height $width; then
      PROMPT_SECURE=true
   else
      PROMPT_SECURE=false
   fi
   ###
   if ! whiptail --backtitle "Triumph Installer" --title "Review" --yesno "You are about to install with these options:\nDoes this look alright?" $height $width; then
      exit 0
   fi
   if ! whiptail --backtitle "Triumph Installer" --title "Review" --yesno "All data on $PROMPT_DISKNAME will be erased. This is your last chance to abort. Do you want to continue?" $height $width; then
      exit 0
   fi
   clear
}
