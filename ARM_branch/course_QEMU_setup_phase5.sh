
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

# Chapter 9
# phase 5 is performed on the host but in chroot, building the bootloader/init scripts and preparing for a bootable system
# assuming you are still in the VM
# FOLLOWING MUST BE ON VM OR THIS FIRST PHASE OF TAKING OVERLAY SHOULD HAVE BEEN DONE (easily re-done if you restart the VM before taking the checkpoint)

# first, unmount sysfs/procfs/devfs and shutdown the host so the overlay is specific to the lfs target
mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm
umount $LFS/dev/pts
umount $LFS/{sys,proc,run,dev}

#### SHUTDOWN THE VM at this point
# make a new overlay
qemu-img create -f qcow2 -b lfs-target-phase4.qcow2 -F qcow2 lfs-target-phase5.qcow2
chmod -w lfs-target-phase4.qcow2

# start VM with phase5 lfs image still as target
QDRIVE1="-drive file=build-host-phase4.qcow2,if=virtio,format=qcow2"
QDRIVE2="-drive file=lfs-target-phase5.qcow2,if=virtio,format=qcow2"
QEFI_RO="-drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
QEFI_RW="-drive if=pflash,format=raw,file=build-host-vars.fd"
qemu-system-aarch64   -M virt -accel hvf -cpu host -smp 4 -m 8192   $QEFI_RO  $QEFI_RW $QDRIVE1 $QDRIVE2  -device qemu-xhci -device usb-kbd -device usb-tablet -netdev user,id=n0,hostfwd=tcp::2222-:22 -nographic -device virtio-net-pci,netdev=n0

# FOLLOWING MUST BE ON VM
sudo su
export LFS=/mnt/lfs

# re-enable the virtualfs mounts (note this is an echo "" informational line):
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm

### Enter Chroot ###
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login


# bootscripts - SysV Init
PKGNAME="lfs-bootscripts-20250827"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
# WORK: stop a moment and look around in this dir, these scripts are the init scripts and will generate the full sysvinit package
make install
# WORK: this will show you where all the boot scripts get symlinked to - this is all inherited from the 1983 original Bell labs sysvinit
# there are better init systems, but since these are all shell scripts, they are understandable in a single sitting
# whereas systemd now has 33 manpages (condensed from over 200 just a few years ago) and 
# contains many possible options (and handles things many *nix users wish it wouldn't)
# configuring systemd for embedded systems means going against several defaults (e.g. killing processes when a user logs out)
# and the developers are hostile to users wanting to do things that aren't the "right" way.
# there are several viable options today: openrc (used in android, alpine, gentoo, among others), s6 (option in gentoo and lfs), 
# runit (void linux), dinit (Artix), BSD-init, and of course sysvinit
# however, expect to encounter systemd as it is supported by Red Hat and Microsoft, and controversially 
# became the default in debian against over half the community (also used in redhat, arch and most debian derivatives)
# devuan is a managed fork of debian that can use either openrc or sysvinit
# valid complaints about sysvinit include: speed (execution of boot scripts is sequential), configurability (not bad on your own system, but painful for
# a distribution to support variety of hardware configurations), and of course, one of the two big problems in computing: naming (inherited)

# this brings us to another problem inherited from halfway between sysvinit and now, the introduction of devfs in linux in 2000,
# specifically, how do you set up the device node files? We used to literally set them up with shell scripts (which still works), having the 
# specific device node numbers ready for this purpose. A different pseudofs, sysfs, enabled the complete deprecation of devfs from the kernel 
# because letting the kernel do it made the system much more fragile to customizers and users (and there were famous race conditions)
# (there is still a devfs, only, it is not the responsibility of the kernel, which it was for only a few years until it could be removed)
# so now, sysfs is how device drivers advertise themselves, and a userspace utility, udev (or systemd-udev) manages the devfs in a far 
# more configurable way now called devtmpfs
# side note on predictable naming to be supplied in the discussion...

## generate initial udev rules
bash /usr/lib/udev/init-net-rules.sh
## inspect the rules for network device naming
cat /etc/udev/rules.d/70-persistent-net.rules
## WORK: surprise! this file doesnt exist - read the generation script and try to think why

## find out your IP address, gateway, netmask (convert to bytes masked off -> prefix) and broadcast (set by qemu)
cd /etc/sysconfig/
cat > ifconfig.eth0 << "EOF"
ONBOOT=yes
IFACE=enp0s3
SERVICE=ipv4-static
IP=10.0.2.15
GATEWAY=10.0.2.2
PREFIX=24
BROADCAST=10.0.2.255
EOF

cat > /etc/resolv.conf << "EOF"
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

## decide on a hostname and set it and the hosts file
echo "nanolfs" > /etc/hostname

cat > /etc/hosts << "EOF"
127.0.0.1 localhost.localdomain localhost
127.0.1.1 nanolfs.example.org nanolfs
10.0.2.15 nanolfs.example.org nanolfs
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
EOF

## create the inittab init will use for configuration
## this is where you can add or remove serial ports/terminals
cat > /etc/inittab << "EOF"
id:3:initdefault:

si::sysinit:/etc/rc.d/init.d/rc S

l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

su:S06:once:/sbin/sulogin
s1:1:respawn:/sbin/sulogin

1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600
3:2345:respawn:/sbin/agetty tty3 9600
4:2345:respawn:/sbin/agetty tty4 9600
5:2345:respawn:/sbin/agetty tty5 9600
6:2345:respawn:/sbin/agetty tty6 9600
EOF


## configure system clock

cat > /etc/sysconfig/clock << "EOF"
UTC=1
# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=
EOF

## configure terminals - this can get highly specific and require debugging with kbd utilities
## and the use of "locale -a" to list all possible charsets

cat > /etc/sysconfig/console << "EOF"
UNICODE="1"
FONT="Lat2-Terminus16"
EOF

## for my usage, I'll stick with en_US.iso88591 charset
cat > /etc/profile << "EOF"
for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  export LANG=en_US.iso88591
fi

# End /etc/profile
EOF

## LFS defaults for inputrc (how special character handling is configured, e.g. backspace, etc)
cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF

cat > /etc/shells << "EOF"
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
EOF

#### Make the system bootable (configure the kernel and bootloader)
## First, what disk is your LFS target at? likely /dev/vdb1 - however, when you boot without build-host<>.qcow2 and only with lfs-phase6,
## then it will enumerate as /dev/vda1
## also, you may or may not have swap (I left 2GB free in case we needed it, it would be at /dev/vda2)
cat > /etc/fstab << "EOF"
# file system  mount-point    type     options             dump  fsck
#                                                                order
/dev/vda1      /              ext4    defaults            1     1
#/dev/<yyy>     swap           swap     pri=1               0     0
proc           /proc          proc     nosuid,noexec,nodev 0     0
sysfs          /sys           sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts       devpts   gid=5,mode=620      0     0
tmpfs          /run           tmpfs    defaults            0     0
devtmpfs       /dev           devtmpfs mode=0755,nosuid    0     0
tmpfs          /dev/shm       tmpfs    nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2  nosuid,noexec,nodev 0     0
EOF

## and now the kernel
cd /sources
tar xf linux-6.17.3.tar.xz
cd linux-6.17.3
# first clean and prepare the kernel sources
make mrproper
# now the big ncurses-based menu
make menuconfig
# or let the package's tools try to figure out your current config
make defconfig
# and _then_ (after defconfig), run make menuconfig to find the options you want to customize
# for example, we'll want plan9 file support (so we can mounthost file dirs in qemu - there are other ways to do it, but its a good one to explore)
##### EXAMPLE CONFIG OPTIONS - these should end up set when you inspect .config, but are findable via the menu - I pretty much _always_ walk the entire
##### menu, it doesn't take that long, nearly all options that are set can be left and nearly all that are unset can be left
# see the kernel_options_aarch64.txt file for a complete list
# WORK: use unix shell utilities to quickly parse and find what is missing
# also, will now need to append the relevant console with -append "console=ttyAMA0" (ttyS0 on x86)

make
# Optional - there are numerous modules turned on by defconfig but it should be safe to skip this (try skipping it)
make modules_install

## setup the /boot folder - basename of the target should be either vmlinuz or Image, typically should contain the version and system tag as well:
# however, here the arm64 instructions at LFS are incorrect, inspect the arch/<> directories to find what was built

cp -iv arch/arm64/boot/Image /boot/vmlinuz-6.17.3-lfs-arm64
# System.map for debugging
cp -iv System.map /boot/System.map-6.17.3
# good to enable /proc/config, but if mounting this disk on a different base (with different kernel/config), copy the .config
# note however, if its to be a shared system, it would be good to NOT enable /proc/config (and also ensure /boot is NOT readable)
cp -iv .config /boot/config-6.17.3
# documentation
cp -r Documentation -T /usr/share/doc/linux-6.17.3

# keep the linux source as is, you can quickly modify it by running make menuconfig and make

## Set up grub - note the naming convention differs (e.g. (hd0,1) instead of /dev/vda1)
# first, assume (you can check with fdisk -l) there is an EFI partition present and mount it
mkdir -pv /boot/efi
mount /dev/vda1 /boot/efi
grub-install --removable

## configure (note the paths carefully)
cat > /boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set root=(hd0,1)

insmod efi_gop

menuentry "GNU/Linux, Linux 6.17.3-lfs-arm64" {
        linux   /boot/vmlinuz-6.17.3-lfs-arm64 root=/dev/vda1 ro
}
EOF

# ensure you copy the kernel across (you will likely need it for qemu command line)
scp -P 2222 nano@localhost:/mnt/lfs/boot/vmlinuz-6.17.3-lfs-arm64 .

##### DONE! shutdown the build-host ####
# take one more overlay
qemu-img create -f qcow2 -b lfs-target-phase5.qcow2 -F qcow2 lfs-target-boot.qcow2
QDRIVE="-drive file=lfs-target-boot.qcow2,if=virtio,format=qcow2"
# startup is modestly different - no vars UEFI (this is the EFI partition that mutates) and we supply the stock BIOS UEFI (readonly)
qemu-system-aarch64   -M virt -accel hvf -cpu host -smp 4 -m 8192 $QDRIVE -kernel boot/vmlinuz-6.17.3-lfs-arm64 -append "console=/dev/ttyAMA root=/dev/vda1"  -device qemu-xhci -device usb-kbd -device usb-tablet -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 -bios edk2-aarch64-code.fd -nographic -serial mon:stdio

## You are hoping to see:
INIT: Entering runlevel: 3
## if you see this line, boot has completed and the system is ready - however, you can't talk to it, 
# so now, we need to do some surgery using the previous qemu boot-up withing the build-host 
# (and this lfs-target-boot.qcow2 image as the second device again)
# you will need to kill the qemu process - note we added "-serial mon:stdio", this enables
# the qemu monitor, use Ctrl-a then c to enter the qemu monitor (alternatively you could start with graphics)
# then "system_powerdown" and "quit" and you'll be back outside the VM

# the final phase is to get this running with a terminal and then set up networking

