
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

# Chapter 5 - cross binutils, gcc, glibc, libstdc++
# phase 1 is performed with the ubuntu compiler and libraries - we must first build the tools for cross-compilation
# move /bin/sh to link to /bin/bash (this is temporary but needed for likely bashisms in the build scripts)
sudo rm /bin/sh
sudo ln -s /bin/bash /bin/sh

# switch to lfs user
su - lfs

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

make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h

cd $LFS/sources
tar xf linux-6.16.1.tar.xz
cd tar xf linux-6.16.1
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr

cd $LFS/sources
tar xf glibc-2.42.tar.x
cd tar xf glibc-2.42
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

# re-unzip gcc (delete to save space)
tar xf gcc-15.2.0.tar.xz
mkdir build; cd build
../libstdc++-v3/configure      \
    --host=$LFS_TGT            \
    --build=$(../config.guess) \
    --prefix=/usr              \
    --disable-multilib         \
    --disable-nls              \
    --disable-libstdcxx-pch    \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
make
make DESTDIR=$LFS install
# remove libtool archives
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la

exit
sudo rm /bin/sh
sudo ln -s /bin/dash /bin/sh

