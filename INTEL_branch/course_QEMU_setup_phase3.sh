
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

# Chapter 7
# phase 3 is performed with the second-pass cross-compile tools in a chrooted environment
# this will complete the temporary system tools we will use to build the final system
# these tools will be inovked within a chroot'ed environment (change-root), so the tools will behave as if they are in their own system
# the kernel under the hood is still that of the base build operating system (e.g. Ubuntu-26.04)

# reminder, start with phase3 overlay
QDRIVE2="-drive file=lfs-target-phase3.qcow2,if=virtio,format=qcow2"
QDRIVE1="-drive file=build-host-phase1.qcow2,if=virtio,format=qcow2"
QEFI_RO="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"
QEFI_RW="-drive if=pflash,format=raw,file=OVMF_VARS-build-host.fd"
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 --enable-kvm \
  $QEFI_RO $QEFI_RW $QDRIVE1 $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0

# now, you must "become superuser"
sudo su

# set the one ENV variable needed below (change if you decided to mount somewhere else)
export LFS=/mnt/lfs
# change ownership from lfs to root - lfs only exists on the build host
chown -R --from lfs root:root $LFS
# prepare target dirs for virtualfs mounts
mkdir -pv $LFS/{dev,proc,sys,run}
# and bind-mount all of /dev, then mount the virtualfs's appropriately
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
# ensure $LFS/dev/shm is its own tmpfs
if [ -h $LFS/dev/shm ]; then
    install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
    # on ubuntu, this will be the case
    mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

### Enter Chroot ###
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

# WORK: notice the command line says "I have no name", that is because the PS1 (this is the 
# commandline prompt) has \u - this tells bash to get the name for the current uid from /etc/passwd, which does not yet exist
# play around, look inside the /proc - its the same as the host so there are many processes - almost all (except the current bash shell) are host processes
# for example, here is the ENV for the current bash shell inside the chroot:
cat proc/$$/environ
# see what libs are linked in the current bash - note these are all inside the chrooted environment
cat /proc/$$/maps
# you should see several libraries that exist in chroot that DO NOT EXIST in the host, e.g. /usr/lib/libc.so.6 (check in non-chrooted/normal shell on the host)
# some however are in both host and chrooted env, e.g. /usr/lib/ld-linux-aarch64.so.1
# this is merely a matter of how the distribution decided to package things - LFS made their own choices, 
# and by the conclusion of this project, you should be able to as well (if you ever need to)


# make required root-level directories
mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
# everything above will have perms 0755, two dirs need special attention to change these perms to standard defaults
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

# Optional: add a warning to your login - check that "/usr/lib64" does not exist and that the virtualfs dirs are mounted

# create the /etc/mtab file that tracks what is currently mounted
ln -sv /proc/self/mounts /etc/mtab

# create /etc/hosts file with defaults for localhost in ipv4 and ipv6
cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

# create passwd file
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

# create tester user (will delete later)
echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester

# re-exec the login shell (only practical impact will be to fix the username in the PS1 prompt)
exec /usr/bin/bash --login

# create the login-monitoring files (note, this functionality will need to change by year 2038 due to use of 32-bit timestamps)
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

# return to building chapter 7 programs - note no more use of $LFS while in chroot

PKGNAME="gettext-0.26"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
./configure --disable-shared
make
# only need three programs from gettext at this stage
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin

PKGNAME="bison-3.8.2"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
make; make install

PKGNAME="perl-5.42.0"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.42/core_perl     \
             -D archlib=/usr/lib/perl5/5.42/core_perl     \
             -D sitelib=/usr/lib/perl5/5.42/site_perl     \
             -D sitearch=/usr/lib/perl5/5.42/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
make; make install

PKGNAME="Python-3.14.0"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
./configure --prefix=/usr       \
            --enable-shared     \
            --without-ensurepip \
            --without-static-libpython
make; make install

PKGNAME="texinfo-7.2"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
./configure --prefix=/usr
make; make install

mkdir -pv /var/lib/hwclock
PKGNAME="util-linux-2.41.1"
cd /sources
tar xf $PKGNAME.tar.xz; cd $PKGNAME
./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.1
make; make install

# remove doc files, will replace them later
rm -rf /usr/share/{info,man,doc}/*
# remove other unneeded files
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools

# exit chroot -note, you will still be running as root, due to the sudo su above
exit

# note, if you will be rebooting, unmount the tmpfs/sysfs/procfs - note again, this must be run as root
mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm
umount $LFS/dev/pts
umount $LFS/{sys,proc,run,dev}

# if you then come back to this stage again later, remount and chroot
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi
# and chroot
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

# shutdown and snapshot by creating an overlay we will then work upon (so next qemu run must reference the overlay, which also loads the build-host and lfs-target)
# note, the build-host is identical past phase0 (phase0 is setup of lfs dir and user prep)
qemu-img create -f qcow2 -b lfs-target-phase3.qcow2 -F qcow2 lfs-target-phase4.qcow2
qemu-img create -f qcow2 -b build-host-phase1.qcow2 -F qcow2 build-host-phase4.qcow2

# NOTE: any changes in the previous layer (e.g. build-host.qcow2) DO NOT get propagated properly, and could lead to conflicts
# so, alternatively, flatten an overlay (and the base+previous overlay images linked by reference in the header) to a distributable single file
qemu-img convert -O qcow2 lfs-target-phase3.qcow2 golden-lfs-target-phase3.qcow2

# so either way, make sure you are referencing the correct layer
QDRIVE1="-drive file=build-host-phase4.qcow2,if=virtio,format=qcow2"
QDRIVE2="-drive file=lfs-target-phase4.qcow2,if=virtio,format=qcow2"

