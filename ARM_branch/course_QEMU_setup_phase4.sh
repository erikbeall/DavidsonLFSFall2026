
# Chapter 8
# phase 4 is performed on the host but in chroot, building the rest of the base system using the cross-compile tools
# this is NOT detailed explicitly here, instead, refer to Chapter 8 of the online guide
# most of the packages are indeed required but some are purely personal choices (systemd, tcl & expect)

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
#
# Chapter 8 is 84 packages and the better part of a day of wall-clock time, and
# it is almost entirely "./configure && make && make install" with per-package
# warts.  You already learned that in Chapters 5-7.  So there is a REAL,
# RUNNABLE script next to this one that does the whole chapter:
#
#     cp automated_course_QEMU_setup_phase4.sh $LFS/root/     # BEFORE chrooting
#     ...chroot as above...
#     bash /root/automated_course_QEMU_setup_phase4.sh        # inside the chroot
#
# Read its header first - it lists every place it deviates from the book (test
# suites skipped by default, three interactive prompts answered from variables
# at the top of the file).  It is resumable: if the VM dies at package 57, run
# it again and it picks up where it left off.  Useful flags:
#
#     --list            what is built and what is not
#     --only <pkg>      build one package
#     --from <pkg>      resume at a package
#     --redo <pkg>      forget a package and rebuild it
#     --dry-run         print the plan, build nothing
#     LFS_RUN_TESTS=1   run the test suites the way the book intends
#
# Run it under screen or tmux, or over the ssh port-forward, so a dropped
# console does not kill the build:
#
#     screen -S ch8
#     bash /root/automated_course_QEMU_setup_phase4.sh 2>&1 | tee /root/ch8.log
#     # detach with ctrl-a d, come back with: screen -r ch8
#
# Chapters 9 and 10 you do BY HAND - that is where the interesting decisions
# are (bootscripts, fstab, kernel config, bootloader), and there is far less of
# it to type.

