
echo "THIS IS NOT A SHELL SCRIPT"
echo "this is a "pseudo" shell script, a shell-like documentation you cannot directly run"
echo "Reading this file shows copy-pasteable commands, intended for aiding progress but only if you are paying attention"
exit 0

# Chapter 6
# phase 2 is performed with the cross-compile tools
# move /bin/sh to link to /bin/bash (this is temporary but needed for likely bashisms 
# in the build scripts until we get to the chroot phase where we're running off binaries in the lfs-target)
sudo rm /bin/sh
sudo ln -s /bin/bash /bin/sh

# switch to lfs user
su - lfs

# build m4
cd $LFS/sources
tar xf m4-1.4.20.tar.xz
cd m4-1.4.20
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)

make
make DESTDIR=$LFS install

cd $LFS/sources
tar xfz ncurses-6.5-20250809.tgz
cd ncurses-6.5-20250809
# first build tic tool
mkdir build
pushd build
  ../configure --prefix=$LFS/tools AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic $LFS/tools/bin
popd
# now configure and built ncurses
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            AWK=gawk
make
make DESTDIR=$LFS install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h

cd $LFS/sources
tar xfz bash-5.3.tar.gz
cd bash-5.3
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc

make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh

cd $LFS/sources
tar xvf coreutils-9.7.tar.xz
cd coreutils-9.7
# patches are not needed at this time (i8n and character boundary recognition patch for POSIX compliance)
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime

make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8

cd $LFS/sources
tar xf diffutils-3.12.tar.xz
cd diffutils-3.12
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            gl_cv_func_strcasecmp_works=y \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install

cd $LFS/sources
tar xf file-5.46.tar.xz
cd file-5.46
# make temporary copy of file (needed for signature generation
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la

cd $LFS/sources
tar xf findutils-4.10.0.tar.xz
cd  tar xf findutils-4.10.0
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf gawk-5.3.2.tar.xz
cd gawk-5.3.2
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf grep-3.12.tar.xz
cd grep-3.12
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf gzip-1.14.tar.xz
cd gzip-1.14
./configure --prefix=/usr --host=$LFS_TGT
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xfz make-4.4.1.tar.gz
cd make-4.4.1
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf patch-2.8.tar.xz
cd patch-2.8
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf sed-4.9.tar.xz
cd sed-4.9
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf tar-1.35.tar.xz
cd tar-1.35
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make; make DESTDIR=$LFS install

cd $LFS/sources
tar xf xz-5.8.1.tar.xz
cd xz-5.8.1
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.8.1
make; make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la

### SECOND PASS ###
# binutils rebuild
cd $LFS/sources
tar xf binutils-2.45.tar.xz
cd binutils-2.45
sed '6031s/$add_dir//' -i ltmain.sh
mkdir build; cd build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make; make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}

cd $LFS/sources
tar xf gcc-15.2.0.tar.xz
cd gcc-15.2.0
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
# ARM64-specific:
sed -e '/lp64=/s/lib64/lib/' -i.orig gcc/config/aarch64/t-aarch64-linux
sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir build
cd build
../configure                   \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --target=$LFS_TGT          \
    --prefix=/usr              \
    --with-build-sysroot=$LFS  \
    --enable-default-pie       \
    --enable-default-ssp       \
    --disable-nls              \
    --disable-multilib         \
    --disable-libatomic        \
    --disable-libgomp          \
    --disable-libquadmath      \
    --disable-libsanitizer     \
    --disable-libssp           \
    --disable-libvtv           \
    --enable-languages=c,c++   \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc

make; make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc

exit
sudo rm /bin/sh
sudo ln -s /bin/dash /bin/sh

