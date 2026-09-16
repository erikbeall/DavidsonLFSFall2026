
# Chapter 8
# phase 4 is performed on the host but in chroot, building the rest of the base system using the cross-compile tools
# this is NOT detailed explicitly here, instead, refer to Chapter 8 of the online guide
# most of the packages are indeed required but some are purely personal choices
# as of v13.0 of LFS, they only support systemd - it has its pluses and minuses, but for understanding a system it is much less helpful
# but knowing systemd is more likely to help you in the future (debian variants and red hat rely on it, alpine variants do not)

sudo su
export LFS=/mnt/lfs

# if you have rebooted the host, re-enable the virtualfs mounts (note this is an echo "" informational line):
echo "mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi"

### Enter Chroot ###
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

# many packages, one after the other...

