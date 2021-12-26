#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE

user_prompts ()
{
   mv /usr/share/zoneinfo/right /usr/share/right
   mv /usr/share/zoneinfo/posix /usr/share/posix
   lsblk | awk '/disk/ {print $1 " " $4 " off"}' > disks.txt
   find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sed -e 's/$/ "" off/' > zones.txt
   TEMP=$(dialog --stdout \
      --msgbox "Welcome to linux-installer! Please answer the following questions to begin." 0 0 \
      --and-widget --clear --radiolist "Choose disk to install to." 0 0 $(wc -l < disks.txt) --file disks.txt \
      --and-widget --clear --radiolist "What distro do you want to install?" 0 0 0 arch "" on debian "" off fedora "" off opensuse "" off void "" off \
      --and-widget --clear --radiolist "Choose a timezone." 0 0 $(wc -l < zones.txt) --file zones.txt \
      --and-widget --clear --inputbox "What will the hostname of this computer be?" 0 0 \
      --and-widget --clear --inputbox "Enter your username." 0 0 \
      --and-widget --clear --passwordbox "Enter your password." 0 0 \
      --and-widget --clear --passwordbox "Confirm password." 0 0 \
   )
   rm disks.txt zones.txt
   if [ "$(echo $TEMP | awk '{print $6}')" != "$(echo $TEMP | awk '{print $7}')" ]; then echo "Passwords do not match"; exit 1; fi
   DISKNAME=$(echo $TEMP | awk '{print $1}')
   DISTRO=$(echo $TEMP | awk '{print $2}')
   TIME=$(echo $TEMP | awk '{print $3}')
   HOST=$(echo $TEMP | awk '{print $4}')
   USER=$(echo $TEMP | awk '{print $5}')
   PASS=$(echo $TEMP | awk '{print $6}')
   if dialog --yesno "Do you want hibernation enabled (Swap partition)" 0 0; then
      SWAP=y
   else
      SWAP=n
   fi
   if dialog --default-button "no" --yesno "This will delete all data on selected storage device. Are you sure you want to continue?" 0 0; then
      SURE=y
   else
      exit 1
   fi
   mv /usr/share/right /usr/share/zoneinfo/right
   mv /usr/share/posix /usr/share/zoneinfo/posix
   clear
}
