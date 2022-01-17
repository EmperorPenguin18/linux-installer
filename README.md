# linux-installer
Universal GNU+Linux installer script

Support for Arch, Debian stable, latest Fedora, openSUSE Tumbleweed and Void included. These distros are chosen because they each have a unique package manager. Goal is to support as much hardware as possible. Currently only supports limited install options.

### Features:
- EFI and Legacy booting
- Choice of yes/no swap (sized for hibernate support)
- BTRFS filesystem with subvolumes and fstab configured
- SATA and NVMe drives
- Install multiple distros from one iso
- AMD and Intel x86_64 CPUs
- Support for being installed inside VirtualBox and KVM/QEMU
- SSDs and HDDs
- Encrypted root+swap partition
- Performance kernels when available
- Fish shell
- GRUB bootloader

### How to use:
1. Boot into an Arch environment. Latest live iso recommended.
2. Make sure your target drive is attached and internet is connected.
3. Run this command with root privileges:
```
curl -sL https://raw.github.com/EmperorPenguin18/linux-installer/main/install.sh | sh
```
4. Answer prompts. Currently not very user friendly. If you've done an Arch install manually before you should know the terms.
5. Wait for installation to complete.
6. Boot away! Only the most basic packages are installed so the rest is up to you. But thats the fun part right? :)

### Future:
- Support ARM processors (single-board computers, new macbooks)
- Add Gentoo, bedrock, alpine, and exherbo, freebsd, guix
- Remove bash (replace with dash for scripts and fish for users)

### Known issues:
- Can't use NVMe drives with Legacy boot

If this script doesn't work for your hardware create an issue. I can't test everything, but I'd like as much hardware as possible to work.
