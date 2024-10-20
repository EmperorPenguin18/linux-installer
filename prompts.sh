#!/bin/sh

#linux-installer by Sebastien MacDougall-Landry
#License is available at
#https://github.com/EmperorPenguin18/linux-installer/blob/main/LICENSE

function user_prompts() {
   PROMPT_DISTRO="arch"
   PROMPT_EFI="no"
   PROMPT_SECURE="no"
   PROMPT_DISKNAME="vda"
   PROMPT_FSTYPE="ext4"
   PROMPT_ENCRYPT="no"
   PROMPT_PASS="password"
   PROMPT_USER="testuser"
   PROMPT_HOST="testcomputer"
   PROMPT_ARCH="x86_64"
   PROMPT_VARIANT="default"
   PROMPT_TARGET="i386-pc"
   clear
}
