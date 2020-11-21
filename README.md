# linux-installer
Universal GNU+Linux installer script

Support for Arch, Debian buster, Fedora 33, and Void included. These distros are chosen because they each have a unique package manager. Goal is to support as much hardware as possible. Made to work how I like things so if you want it to do something else fork away.

Features:
- EFI and Legacy booting
- Choice of yes/no swap (sized for hibernate support)
- BTRFS filesystem with subvolumes and fstab configured
- SATA and NVMe drives
- Install multiple distros from one iso
- AMD and Intel x86_64 CPUs
- Support for being installed inside VirtualBox and KVM/QEMU
- SSDs and HDDs
- GRUB as bootloader
- Full encrypted disk
- Performance kernels
- doas used instead of sudo

How to use:
1. Must be run from an Arch environment. Latest live iso recommended.
3. Make script executable (chmod +x) and run it with root privileges. (./install.sh)
4. Answer prompts. Just covers the basics.
5. Wait for installation to complete.
6. Boot away! Only the most basic packages are installed so the rest is up to you. But thats the fun part right? :)

Future:
- Support ARM processors (single-board computers, new macbooks)

Bugs:
- Can't use NVMe drives with EFI boot

If this script doesn't work for your hardware create an issue. I can't test everything, but I'd like as much hardware as possible to work.
