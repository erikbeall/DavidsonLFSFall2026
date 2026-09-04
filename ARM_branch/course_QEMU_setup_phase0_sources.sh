
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

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
fdisk -p /dev/vdb

# should look like:
echo '
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda                       253:0    0   60G  0 disk
├─vda1                    253:1    0    1G  0 part /boot/efi
├─vda2                    253:2    0    2G  0 part /boot
└─vda3                    253:3    0 56.9G  0 part
  └─ubuntu--vg-ubuntu--lv 252:0    0 28.5G  0 lvm  /
vdb                       253:16   0   20G  0 disk
├─vdb1                    253:17   0   18G  0 part
└─vdb2                    253:18   0    2G  0 part
'

# add a mount line to /etc/fstab:
# /dev/vdb1	/mnt/lfs	ext4 defaults 0 1
# and if needed, add a line for swap (I intentionally left 2GB in case we run out of RAM in this VM)
# (only do this if you are running out of RAM, might never be needed as there is a pseudo swap of 4GB already present)
#/dev/vdb2	none	swap	sw	0	0

sudo mkfs.ext4 /dev/vdb1
sudo mkswap /dev/vdb2
sudo swapon /dev/vdb2

# new files create with 0644 and new dirs with 0755
umask 022

mkdir $LFS
sudo mount -v -t ext4 /dev/vdb1 $LFS

# make the sources directory first, start the wget processing and move on in CONTINUE PREPARATIONS
sudo mkdir $LFS/sources
sudo chown $USER:$USER $LFS/sources
cd $LFS/sources
# make sources dir "sticky" so only owner can delete - entirely optional
chmod -v a+wt $LFS/sources

# get the curated list of sources and their md5sums for verification
wget -c   https://www.linuxfromscratch.org/lfs/view/12.4/wget-list-sysv
wget -c   https://www.linuxfromscratch.org/lfs/view/12.4/md5sums

# get all sources
wget -c   --input-file=./wget-list-sysv --directory-prefix=$LFS/sources
# NOTE, this can take some time, feel free to open a second ssh localhost session and proceed with setting 
# up the LFS installation target disk and come back to the md5sum verification step
# really, the md5sum verification often exposes broken links which need to be followed up manually (so you learn how to do it)
# and that will complete phase0 setup

# verify all sources
md5sum -c md5sums
# should report OK for every package, no missing files or otherwise
# may need to hunt around as mirrors do change, e.g. wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz
# or use the LFS mirrors: wget https://lfs.gnlug.org/pub/lfs/lfs-packages/12.0/gcc-13.2.0.tar.xz etc

# for x86_64, use the systemd main
# wget -c https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/wget-list-systemd
# wget -c https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/md5sums

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

# (as root) remove the system's default bashrc, can replace it later (lfs does NOT use a default bashrc)
mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

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

