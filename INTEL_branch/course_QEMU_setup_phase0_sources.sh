
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

#### NOTE: this takes place within the emulator, NOT the WSL Ubuntu ###
# start qemu within WSL (or bare metal windows, with the appropriate accel and command line changes)
QDRIVE1="-drive file=build-host-phase0.qcow2,if=virtio,format=qcow2"
QDRIVE2="-drive file=lfs-target.qcow2,if=virtio,format=qcow2"
QEFI_RO="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"
QEFI_RW="-drive if=pflash,format=raw,file=OVMF_VARS-build-host.fd"
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 \
  $QEFI_RO $QEFI_RW $QDRIVE1 $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0

# for chapters 1-4, everything is done without touching the new LFS disk
# for chapters 5 & 6, must mount the lfs partition and work as user "lfs", with "su - lfs"
# for chapters 7-10, work will be done with pseudo filesystems mounted and via a chrooted environment

# steps to prepare the build host, including downloading sources

sudo apt update
sudo apt upgrade
sudo dpkg-reconfigure dash
sudo apt install gcc g++ bison make git texinfo

export LFS=/mnt/lfs

# Set up the LFS installation target disk - in this case its a single image qcow2 that does not yet have partitions
# so we will add them, via fdisk, first decide on a partition strategy, here's suggested:
sudo fdisk -l /dev/vdb
# should look like:
Disk /dev/vdb: 20 GiB, 21474836480 bytes, 41943040 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes

# alternatively, use lsblk
# should look like:
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda                       253:0    0   60G  0 disk
├─vda1                    253:1    0    1G  0 part /boot/efi
├─vda2                    253:2    0    2G  0 part /boot
└─vda3                    253:3    0 56.9G  0 part
  └─ubuntu--vg-ubuntu--lv 252:0    0 28.5G  0 lvm  /
vdb                       253:16   0   20G  0 disk
# this indicates there are not yet any partitions or filesystems on the to-be-installed disk (vdb), 
# whereas the rootfs disk (vda) already has three partitions (ubuntu made decisions on which partitions to use)
# we must partition and make the filesystem data structures:
sudo fdisk /dev/vdb
# add a partition, make it take most of the space (for building), leave 2GB in case we need swap (unlikely)
# use "n" (for new), "p" (for primary), default number and start sector (2048) and then type +18G for the size
# repeat, accepting default start and end, which will create a second partition of size 2GB
# now type "p" to "print" the table so far:
Device     Boot    Start      End  Sectors Size Id Type
/dev/vdb1           2048 37750783 37748736  18G 83 Linux
/dev/vdb2       37750784 41943039  4192256   2G 83 Linux

# finally, "w" to write the table and exit fdisk
# next, set the large partition to be an ext4 filesystems by creating the filesystem structure:
sudo mkfs.ext4 /dev/vdb1

# make a mount point for the new target disk
sudo mkdir $LFS
# note, the env var LFS is /mnt/lfs, if you decide to put it somewhere else, make sure you change references to it below

# add a mount line to /etc/fstab:
/dev/vdb1	/mnt/lfs	ext4 defaults 0 1
# NOTE, there is a MUCH better way to reference a block device in linux than by device/node numbering, 
# because it can change based on boot flags, if interested, get the UUID of the vdb1 device with:
sudo blkid
# note how this is used in /etc/fstab

# POSSIBLY NOT NEEDED, unless you are not able to give qemu 8GB of RAM
# and if needed, add a line in /etc/fstab for swap (I intentionally left 2GB in case we run out of RAM in this VM)
# (only do this if you are running out of RAM, might never be needed as there is a pseudo swap of 4GB already present in qemu)
#/dev/vdb2	none	swap	sw	0	0
# sudo mkswap /dev/vdb2
# sudo swapon /dev/vdb2

# new files create with 0644 and new dirs with 0755
umask 022

sudo mount -v -t ext4 /dev/vdb1 $LFS

# make the sources directory first, start the wget processing and move on in CONTINUE PREPARATIONS
sudo mkdir $LFS/sources
# replace <user> with your username, NOT root
sudo chown <user>:<user> $LFS/sources
cd $LFS/sources
# make sources dir "sticky" so only owner can delete - entirely optional
chmod -v a+wt $LFS/sources

# get the curated list of sources and their md5sums for verification (using the most recent amd64 branch)
wget -c   https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/wget-list
wget -c   https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/md5sums

# get all sources
wget -c   --input-file=./wget-list --directory-prefix=$LFS/sources
# NOTE: it is ./wget-list here (the systemd list fetched just above), NOT
# wget-list-sysv - that is the arm64/SysV branch's filename.  The book's list
# includes the .patch files as well as the tarballs; if yours has no patches in
# it, you have the wrong or a trimmed list and Chapter 8 will fail partway in.
# NOTE, this can take some time, feel free to open a second ssh localhost session and proceed with setting 
# up the LFS installation target disk and come back to the md5sum verification step
# really, the md5sum verification often exposes broken links which need to be followed up manually (so you learn how to do it)
# and that will complete phase0 setup

# verify all sources
md5sum -c md5sums
# should report OK for every package, no missing files or otherwise
# may need to hunt around as mirrors do change, e.g. wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz
# or use the LFS mirrors: wget https://lfs.gnlug.org/pub/lfs/lfs-packages/13.1/gcc-13.2.0.tar.xz etc

### CONTINUE PREPARATIONS

# make $LFS/{etc,var}, $LFS/usr/{bin,lib,sbin}
cd $LFS
sudo mkdir boot boot/efi home usr usr/bin usr/lib usr/share usr/sbin opt tmp usr/src
# symlink the real dirs inside $LFS/usr/* to $LFS/
# note for x86_64 also make a $LFS/lib64
sudo ln -s usr/bin bin
sudo ln -s usr/sbin sbin
sudo ln -s usr/lib lib


# make the cross-compiler target dir (this will be removed at a later point when it is no longer needed
sudo mkdir $LFS/tools

# su to root and then add the lfs user:
sudo groupadd lfs
sudo useradd -s /bin/bash -g lfs -m -k /dev/null lfs
sudo passwd lfs

# chown all $LFS/ files to lfs:lfs
sudo chown -R -v lfs:lfs $LFS

# make all packages owned by root so sources cannot be deleted by accident (lfs is not in the sudoers file, intentionally)
sudo chown root:root $LFS/sources/*

# remove the system's default bashrc, can replace it later (lfs does NOT use a default bashrc)
sudo mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

# switch to lfs user
su - lfs

# as lfs, create profile so only env we want gets in there (env variables are notoriously "leaky")
cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF
#
# and then create lfs's .bashrc
cat > ~/.bashrc << "EOF"
set +h # turn off hashing since we'll be switching actual binaries a few times
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
export MAKEFLAGS=-j4 # use the 4 cores available in this qemu (use whatever num of cores you run qemu with)
EOF

# shut down the VM and...
# make an overlay for next work
qemu-img create -f qcow2 -b build-host-phase0.qcow2 -F qcow2 build-host-phase1.qcow2
QDRIVE1="-drive file=build-host-phase1.qcow2,if=virtio,format=qcow2"
# do same for lfs-target disk
qemu-img create -f qcow2 -b lfs-target.qcow2 -F qcow2 lfs-target-phase1.qcow2
QDRIVE2="-drive file=lfs-target-phase1.qcow2,if=virtio,format=qcow2"

# boot with the new phase1 overlays
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 \
  $QEFI_RO $QEFI_RW $QDRIVE1 $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0

