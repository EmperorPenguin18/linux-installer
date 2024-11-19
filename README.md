# linux-installer

A wrapper around LXC to automate installing, add configurability, and only need one ISO to install everything I need.

### How to use:
1. Boot into any Linux environment. Latest Arch iso recommended.
2. Make sure your target drive is attached and internet is connected.
3. Install qemu-img if you don't already have it. Everything else should already be installed.
3. Run this command with root privileges:
```
curl -sL https://raw.github.com/EmperorPenguin18/linux-installer/main/install.sh | sh
```
4. Answer prompts. Currently not very user friendly. If you've done an Arch install manually before you should know the terms.
5. Wait for installation to complete.
6. Boot away! Only the most basic packages are installed so the rest is up to you. But thats the fun part right? :)
