# linux-installer
Universal GNU+Linux installer script

Support for Arch, Debian buster, Fedora 33, and Void included. These distros are chosen because they each have a unique package manager. Goal is to support as much hardware as possible. Made to work how I like things so if you want it to do something else fork away.

Features:
- GPT + EFI booting
- Choice of yes/no swap (sized for hibernate support)
- BTRFS filesystem with subvolumes and fstab configured
- SATA and NVMe drives
- Install multiple distros from one iso
- AMD and Intel x86_64 CPUs
- Support for being installed inside VirtualBox and KVM/QEMU
- SSDs and HDDs
- GRUB as bootloader
- Full encrypted disk
- Performance kernels used instead of standard ones
- doas used instead of sudo because I don't need that much permission management


How to use:
1. Must be run from an Arch live iso.
2. The only drives connected must be the usb and the target drive with no partitions
3. Make script executable (chmod +x) and run with ./install.sh
4. Answer prompts. Not designed to be user friendly, just covers the basics
5. Wait for installation to complete
6. Boot away! Only the most basic packages are installed so the rest is up to you. But thats the fun part right? :)
