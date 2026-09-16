
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

# Chapter 5 - cross binutils, gcc, glibc, libstdc++
# phase 1 is performed with the ubuntu compiler and libraries - we must first build the tools for cross-compilation
# CRITICAL NOTE FOR NON-BASH SYSTEMS:
# move /bin/sh to link to /bin/bash (this is temporary but needed for likely bashisms in the build scripts)
# read up on bashisms - if we were very lucky, each and every makefile would reference /bin/bash, but that is not too likely...
# its a good habit to learn bashisms so when you write shell scripts they are much more likely to be portable (limit to only POSIX shell)
# in fact, GNU autoconf (used by 90% of the core packages) generates a configure shell script with $!/bin/sh at the top - question for
# debian maintainers, how would you deal with this?
sudo rm /bin/sh
sudo ln -s /bin/bash /bin/sh

# make sure $LFS/sources is accessible (writeable) by user lfs:
# if this was not done already, make sure you've followed along in phase0
#sudo chown lfs:lfs

# switch to lfs user
su - lfs

# NOTE: you _should_ have defined LFS in your bashrc, if not, you'll know why very soon...

# build binutils
cd $LFS/sources
tar xvf binutils-2.45.tar.xz
cd binutils-2.45
mkdir build
cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu

make
make install

## STOP HERE FOR A MINUTE - inspect the configure line above - this is still today the way package maintainers build packages
# please make sure you understand the most important modifiers are the prefix and target, 
# (and others, such as sysroot)  -> these set where binutils "thinks" the root filesystem will be located.
# prefix and target are most commonly needed, some packages need to also know where to find other components
# this ends up being a curated "for my distro" set of commands so other package maintainers (and yourself)
# can manage evolving builds
# you'll also see things like disable-shared, or disable-<something else>, some of these are only vital for cross-compiling

# also take a look in /mnt/lfs/tools -> the make install for binutils has now changed that dir

cd $LFS/sources
tar xf gcc-15.2.0.tar.xz
cd gcc-15.2.0
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
mkdir build
cd build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.42 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++

# WORK note we disable libstdcxx, why?
# WORK and that's a good reason to also ask, what is newlib?
# if you're interested in embedded (microcontrollers), look into newlib and uClibc, 
# for when you need things like printf() and don't want to pull in glibc or musl

make
make install
cd ..

# everything you compile will need certain headers, at this point, one will need to be modified
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h

# WORK: did you spot the bashism?
# see https://mywiki.wooledge.org/Bashism and other references

cd $LFS/sources
# version may differ - look closely - copy/paste will fail...
tar xf linux-6.16.1.tar.xz
cd tar xf linux-6.16.1
make mrproper
make headers

# look inside usr/include - more headers necessary to compile most programs
# but it also includes non-header files (cmd, Makefiles)
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr

cd $LFS/sources
tar xf glibc-2.42.tar.xz
cd glibc-2.42
# look at the patch file - these are extremely common in package management, typically these will get pushed to the source
# WORK: in this case, what does this patch do?
patch -Np1 -i ../glibc-2.42-fhs-1.patch
mkdir build; cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib           \
      --enable-kernel=5.4

# WORK: what does disable-nscd do?
# WORK: and what is the purpose of enabling kernels back to 5.4?

make
make DESTDIR=$LFS install
# fixup the hard-coded path to the loader
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd

# for fun, look inside /mnt/lfs/etc - this is installed by the glibc installation
# test the cross-compiler+binutils+glibc
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
# should show the aarch64 ld loader
# check startup files
grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
# should show 3 successes
grep -B3 "^ $LFS/usr/include" dummy.log
# should show appropriate search paths
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
# and check the libc
grep "/lib.*/libc.so.6 " dummy.log
grep found dummy.log
rm -v a.out dummy.log

# gcc again
cd $LFS/sources
cd gcc-15.2.0
# remove the build dir and start again
rm -rf build
mkdir build; cd build
# this time, we're building the libstd++ part - because it calls malloc, memcpy, etc, all from the standard c library, which we didn't have until _AFTER_ gcc above
# note, pch means "pre-compiled headers", not needed
../libstdc++-v3/configure      \
    --host=$LFS_TGT            \
    --build=$(../config.guess) \
    --prefix=/usr              \
    --disable-multilib         \
    --disable-nls              \
    --disable-libstdcxx-pch    \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0

# --host specifically forces use of the cross-compiler
make
make DESTDIR=$LFS install
# remove libtool archives
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la

exit
sudo rm /bin/sh
sudo ln -s /bin/dash /bin/sh

# shutdown
# create overlay for next phase
qemu-img create -f qcow2 -b lfs-target-phase1.qcow2 -F qcow2 lfs-target-phase2.qcow2
QDRIVE2="-drive file=lfs-target-phase2.qcow2,if=virtio,format=qcow2"

# boot with the new phase1 overlays
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 --enable-kvm \
  $QEFI_RO $QEFI_RW $QDRIVE1 $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0

