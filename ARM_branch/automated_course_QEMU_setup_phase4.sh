#!/usr/bin/env bash
#
# automated_course_QEMU_setup_phase4.sh
# =====================================
# UNLIKE the other course_QEMU_setup_phase*.sh files in this directory, THIS ONE
# IS A REAL SCRIPT and is meant to be executed.
#
# It automates Chapter 8 ("Installing Basic System Software") of the arm64 LFS
# book, https://www.linuxfromscratch.org/~xry111/lfs/view/arm64/ , book revision
# arm64-r12.4-42.  Every build command below was lifted verbatim from that book;
# the only edits are the ones listed under "DEVIATIONS FROM THE BOOK" at the
# bottom of this header, and each one is marked in place with a "# COURSE:"
# comment.
#
# WHY THIS SCRIPT EXISTS
#   Chapter 8 is ~84 packages and, with the test suites, the better part of a
#   day of wall-clock time on a 4-core QEMU guest.  Almost all of it is
#   "./configure && make && make install" with package-specific warts.  Typing
#   it out teaches you very little that Chapters 5-7 did not already teach you,
#   and Chapters 9 and 10 (the interesting parts - bootscripts, fstab, kernel
#   config, bootloader) are where you want your remaining time.  So: run this,
#   read the log, and go do Chapter 9 by hand.
#
#   You are still expected to be able to READ this script.  Each package is one
#   shell function, in book order, and the function body is the book's own
#   command list.  Open the book page alongside a function and they should line
#   up one-to-one.
#
# WHERE THIS PICKS UP
#   Run it INSIDE the chroot, as root, after you have done the mount +
#   chroot dance from course_QEMU_setup_phase4.sh (which is still the
#   documentation for that part - read it first).  The script refuses to run
#   if it does not look like it is in the chroot.
#
#   From the host side, that means:
#       sudo su
#       export LFS=/mnt/lfs
#       <the mount -v --bind /dev ... block from course_QEMU_setup_phase4.sh>
#       cp automated_course_QEMU_setup_phase4.sh $LFS/root/
#       chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" \
#           PS1='(lfs chroot) \u:\w\$ ' PATH=/usr/bin:/usr/sbin \
#           MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" /bin/bash --login
#   then, at the (lfs chroot) prompt:
#       bash /root/automated_course_QEMU_setup_phase4.sh
#
# USAGE
#   bash automated_course_QEMU_setup_phase4.sh                  # build everything
#   bash automated_course_QEMU_setup_phase4.sh --list           # show progress
#   bash automated_course_QEMU_setup_phase4.sh --only gcc       # just one package
#   bash automated_course_QEMU_setup_phase4.sh --from gcc       # resume at gcc
#   bash automated_course_QEMU_setup_phase4.sh --redo gcc       # forget gcc, rebuild it
#   bash automated_course_QEMU_setup_phase4.sh --dry-run        # print the plan only
#   LFS_RUN_TESTS=1 bash automated_course_QEMU_setup_phase4.sh  # run the test suites
#
#   It is RESUMABLE.  Each package that finishes drops a stamp file in
#   /var/lib/lfs-phase4/, and a re-run skips anything already stamped.  If the
#   VM dies at package 57, just run it again.
#
# DEVIATIONS FROM THE BOOK (all of them, and why)
#   1. Test suites are SKIPPED by default.  They roughly triple the runtime and
#      several of them (glibc, gcc, binutils) have known, expected failures that
#      would halt an unattended run.  Set LFS_RUN_TESTS=1 to run them the way
#      the book intends.  Every skipped block is still here, inside an
#      "if want_tests" guard, so you can see exactly what you are not running.
#   2. Three interactive steps are answered from variables at the top of the
#      script instead of from a prompt: the timezone (book: tzselect), the root
#      password (book: passwd root), and groff's paper size (book:
#      PAGE=<paper_size>).
#   3. Glibc's "alternatively, install ALL locales" command is dropped - the
#      book offers it as an alternative to the explicit localedef list, and it
#      is slow.  The explicit list is what we run.
#   4. Bash's trailing "exec /usr/bin/bash --login" is dropped.  In the book it
#      re-execs your interactive shell onto the newly installed bash; inside a
#      script it would replace the script itself and the run would end there.
#   5. Vim's "vim -c ':options'" is dropped - it opens an interactive editor.
#   6. GCC's post-install sanity checks (the dummy.log greps) are run for their
#      output but are not allowed to abort the run; read them in the log.
#   7. Section 8.86 "Stripping" is OFF by default (LFS_STRIP=1 turns it on).
#      It saves ~2 GB but makes debugging the resulting system much harder, and
#      it hardcodes library version numbers that drift between book revisions.
#   8. Section 8.87 "Cleaning Up" removes the tester user and the cross-compile
#      leftovers; it runs last, controlled by LFS_CLEANUP (default 1).
#
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------ settings
# These are the answers to the book's interactive prompts.  Change them here
# rather than editing the package functions below.

# Davidson, NC is US Eastern.  `ls /usr/share/zoneinfo` after glibc for others.
LFS_TIMEZONE="${LFS_TIMEZONE:-America/New_York}"

# Book section 8.29.3.  CHANGE THIS, or at least know that you did not.
LFS_ROOT_PASSWORD="${LFS_ROOT_PASSWORD:-lfs}"

# Book section 8.65.  "letter" in the US, "A4" most other places.
LFS_PAPER_SIZE="${LFS_PAPER_SIZE:-letter}"

# Test suites: off by default.  See deviation 1 above.
LFS_RUN_TESTS="${LFS_RUN_TESTS:-0}"

# Section 8.86 Stripping (off) and 8.87 Cleaning Up (on).
LFS_STRIP="${LFS_STRIP:-0}"
LFS_CLEANUP="${LFS_CLEANUP:-1}"

# Delete each package's unpacked source tree once it installs cleanly.  Turn
# this off (0) if you want to poke around in a build afterwards - but the
# sources partition will fill up.
LFS_RM_SOURCES="${LFS_RM_SOURCES:-1}"

# Parallelism.  The chroot env already exports MAKEFLAGS; honour it if set.
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc 2>/dev/null || echo 4)}"
export TESTSUITEFLAGS="${TESTSUITEFLAGS:--j$(nproc 2>/dev/null || echo 4)}"

SOURCES=/sources
STATEDIR=/var/lib/lfs-phase4      # one stamp file per finished package
LOGDIR=/var/log/lfs-phase4        # one log file per package
TOPDIR_FILE=/run/lfs-phase4.topdir

# The packages, in book order.  The name is the book's page name, which is also
# what you pass to --only / --from / --redo.
PACKAGES=(
    "man-pages"
    "iana-etc"
    "glibc"
    "zlib"
    "bzip2"
    "xz"
    "lz4"
    "zstd"
    "file"
    "readline"
    "pcre2"
    "m4"
    "bc"
    "flex"
    "tcl"
    "expect"
    "dejagnu"
    "pkgconf"
    "binutils"
    "gmp"
    "mpfr"
    "mpc"
    "attr"
    "acl"
    "libcap"
    "libxcrypt"
    "shadow"
    "gcc"
    "ncurses"
    "sed"
    "psmisc"
    "gettext"
    "bison"
    "grep"
    "bash"
    "libtool"
    "gdbm"
    "gperf"
    "expat"
    "inetutils"
    "less"
    "perl"
    "xml-parser"
    "intltool"
    "autoconf"
    "automake"
    "openssl"
    "libelf"
    "libffi"
    "sqlite"
    "Python"
    "flit-core"
    "packaging"
    "wheel"
    "setuptools"
    "ninja"
    "meson"
    "kmod"
    "coreutils"
    "diffutils"
    "gawk"
    "findutils"
    "groff"
    "grub"
    "gzip"
    "iproute2"
    "kbd"
    "libpipeline"
    "make"
    "patch"
    "tar"
    "texinfo"
    "vim"
    "markupsafe"
    "jinja2"
    "udev"
    "man-db"
    "procps-ng"
    "util-linux"
    "e2fsprogs"
    "sysklogd"
    "sysvinit"
)

# ------------------------------------------------------------------- helpers

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail] %s\033[0m\n' "$*" >&2; exit 1; }

# want_tests - guards every "make check" block.  See deviation 1.
want_tests() { [ "$LFS_RUN_TESTS" = "1" ]; }

# sanity_check - run a block of diagnostic commands for their output only.  A
# non-zero exit here is reported but never aborts the run (used for GCC's
# post-install checks, where the interesting thing is what gets printed).
sanity_check() {
    local block; block="$(cat)"
    if ! bash -c "$block"; then
        warn "a sanity check reported a problem - read the log for this package"
    fi
}

# unpack <glob> - find exactly one matching tarball in /sources, unpack it, and
# cd into whatever top-level directory it creates.
#
# NOTE for the curious: there is deliberately no case statement on .gz/.xz/.bz2
# here.  GNU tar sniffs the compression itself, so plain `tar -xf` handles every
# extension the book uses (.tar.gz, .tar.xz, .tar.bz2, and ncurses' .tgz).  The
# only thing worth writing code for is (a) resolving the version-numbered
# filename from a glob, so this script survives a book version bump, and (b)
# finding the directory name, which does not always match the tarball name
# (tcl8.6.17-src.tar.gz unpacks to tcl8.6.17/, sqlite-autoconf-* to
# sqlite-autoconf-*/, and so on).
unpack() {
    local glob="$1" matches tarball top
    cd "$SOURCES"

    # shellcheck disable=SC2206
    matches=( $glob )
    [ -e "${matches[0]}" ] || die "no source tarball matching '$glob' in $SOURCES.
    Did phase 0 finish downloading?  Check with: ls $SOURCES"
    [ "${#matches[@]}" -eq 1 ] || die "'$glob' matched ${#matches[@]} files: ${matches[*]}"
    tarball="${matches[0]}"

    echo "--- unpacking $tarball"

    # First path component of the archive listing = the directory it creates.
    #
    # The `set +o pipefail` is load-bearing.  awk quits after the first line,
    # which hands tar a SIGPIPE, which makes tar exit 141.  With pipefail on -
    # and it IS on, for every package build - that 141 becomes the status of the
    # whole pipeline and errexit kills the run before a single package is built.
    # Command substitution is a subshell, so this only relaxes the one pipeline.
    top=$(set +o pipefail
          tar -tf "$tarball" | awk -F/ '$1 != "." && $1 != "" { print $1; exit }')
    [ -n "$top" ] || die "cannot work out the top-level directory of $tarball.
    Is it a complete download?  Try: tar -tf $SOURCES/$tarball | head"

    # A leftover tree from a failed attempt would poison the build.
    rm -rf "${SOURCES:?}/$top"
    tar -xf "$tarball"
    echo "$top" > "$TOPDIR_FILE"          # so the driver can clean up after us
    cd "$SOURCES/$top"
}

# done_stamp / is_done - the resume mechanism.
stamp_of() { echo "$STATEDIR/$1.done"; }
is_done()  { [ -f "$(stamp_of "$1")" ]; }

# fn_for <page-name> - book page name to shell function name.
fn_for() { echo "pkg_$(echo "$1" | tr 'A-Z-' 'a-z_')"; }

# 8.3. Man-pages-6.15
pkg_man_pages() {
    unpack 'man-pages-*.tar.*'

    rm -v man3/crypt*

    make -R GIT=false prefix=/usr install
}

# 8.4. Iana-Etc-20250926
pkg_iana_etc() {
    unpack 'iana-etc-*.tar.*'

    cp services protocols /etc
}

# 8.5. Glibc-2.42
pkg_glibc() {
    unpack 'glibc-[0-9]*.tar.*'

    patch -Np1 -i ../glibc-2.42-fhs-1.patch

    sed -e '/unistd.h/i #include <string.h>' \
        -e '/libc_rwlock_init/c\
      __libc_rwlock_define_initialized (, reset_lock);\
      memcpy (&lock, &reset_lock, sizeof (lock));' \
        -i stdlib/abort.c

    mkdir -v build
    cd       build

    echo "rootsbindir=/usr/sbin" > configparms

    ../configure --prefix=/usr                   \
                 --disable-werror                \
                 --disable-nscd                  \
                 libc_cv_slibdir=/usr/lib        \
                 --enable-stack-protector=strong \
                 --enable-kernel=5.4

    make

    if want_tests; then
        make check

        grep "Timed out" $(find -name \*.out)
    fi

    touch /etc/ld.so.conf

    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile

    make install

    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

    localedef -i C -f UTF-8 C.UTF-8
    localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
    localedef -i de_DE -f ISO-8859-1 de_DE
    localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
    localedef -i de_DE -f UTF-8 de_DE.UTF-8
    localedef -i el_GR -f ISO-8859-7 el_GR
    localedef -i en_GB -f ISO-8859-1 en_GB
    localedef -i en_GB -f UTF-8 en_GB.UTF-8
    localedef -i en_HK -f ISO-8859-1 en_HK
    localedef -i en_PH -f ISO-8859-1 en_PH
    localedef -i en_US -f ISO-8859-1 en_US
    localedef -i en_US -f UTF-8 en_US.UTF-8
    localedef -i es_ES -f ISO-8859-15 es_ES@euro
    localedef -i es_MX -f ISO-8859-1 es_MX
    localedef -i fa_IR -f UTF-8 fa_IR
    localedef -i fr_FR -f ISO-8859-1 fr_FR
    localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
    localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
    localedef -i is_IS -f ISO-8859-1 is_IS
    localedef -i is_IS -f UTF-8 is_IS.UTF-8
    localedef -i it_IT -f ISO-8859-1 it_IT
    localedef -i it_IT -f ISO-8859-15 it_IT@euro
    localedef -i it_IT -f UTF-8 it_IT.UTF-8
    localedef -i ja_JP -f EUC-JP ja_JP
    localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
    localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
    localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
    localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
    localedef -i se_NO -f UTF-8 se_NO.UTF-8
    localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
    localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
    localedef -i zh_CN -f GB18030 zh_CN.GB18030
    localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
    localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

    tar -xf ../../tzdata2025b.tar.gz

    ZONEINFO=/usr/share/zoneinfo
    mkdir -pv $ZONEINFO/{posix,right}

    for tz in etcetera southamerica northamerica europe africa antarctica  \
              asia australasia backward; do
        zic -L /dev/null   -d $ZONEINFO       ${tz}
        zic -L /dev/null   -d $ZONEINFO/posix ${tz}
        zic -L leapseconds -d $ZONEINFO/right ${tz}
    done

    cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York
    unset ZONEINFO tz

    # COURSE: the book runs tzselect here and has you paste the answer in.
    # Set LFS_TIMEZONE at the top of this script instead.
    ln -sfv "/usr/share/zoneinfo/$LFS_TIMEZONE" /etc/localtime

cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF

cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
mkdir -pv /etc/ld.so.conf.d
}

# 8.6. Zlib-1.3.1
pkg_zlib() {
    unpack 'zlib-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install

    rm -fv /usr/lib/libz.a
}

# 8.7. Bzip2-1.0.8
pkg_bzip2() {
    unpack 'bzip2-*.tar.*'

    patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch

    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile

    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

    make -f Makefile-libbz2_so
    make clean

    make

    make PREFIX=/usr install

    cp -av libbz2.so.* /usr/lib
    ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so

    cp -v bzip2-shared /usr/bin/bzip2
    for i in /usr/bin/{bzcat,bunzip2}; do
      ln -sfv bzip2 $i
    done

    rm -fv /usr/lib/libbz2.a
}

# 8.8. Xz-5.8.1
pkg_xz() {
    unpack 'xz-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/xz-5.8.1

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.9. Lz4-1.10.0
pkg_lz4() {
    unpack 'lz4-*.tar.*'

    make BUILD_STATIC=no PREFIX=/usr

    if want_tests; then
        make -j1 check
    fi

    make BUILD_STATIC=no PREFIX=/usr install
}

# 8.10. Zstd-1.5.7
pkg_zstd() {
    unpack 'zstd-*.tar.*'

    make prefix=/usr

    if want_tests; then
        make check
    fi

    make prefix=/usr install

    rm -v /usr/lib/libzstd.a
}

# 8.11. File-5.46
pkg_file() {
    unpack 'file-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.12. Readline-8.3
pkg_readline() {
    unpack 'readline-*.tar.*'

    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install

    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf

    ./configure --prefix=/usr    \
                --disable-static \
                --with-curses    \
                --docdir=/usr/share/doc/readline-8.3

    make SHLIB_LIBS="-lncursesw"

    make install

    install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3
}

# 8.13. Pcre2-10.46
pkg_pcre2() {
    unpack 'pcre2-*.tar.*'

    ./configure --prefix=/usr                       \
                --docdir=/usr/share/doc/pcre2-10.46 \
                --enable-unicode                    \
                --enable-jit                        \
                --enable-pcre2-16                   \
                --enable-pcre2-32                   \
                --enable-pcre2grep-libz             \
                --enable-pcre2grep-libbz2           \
                --enable-pcre2test-libreadline      \
                --disable-static

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.14. M4-1.4.20
pkg_m4() {
    unpack 'm4-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.15. Bc-7.0.3
pkg_bc() {
    unpack 'bc-*.tar.*'

    CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r

    make

    if want_tests; then
        make test
    fi

    make install
}

# 8.16. Flex-2.6.4
pkg_flex() {
    unpack 'flex-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/flex-2.6.4

    make

    if want_tests; then
        make check
    fi

    make install

    ln -sv flex   /usr/bin/lex
    ln -sv flex.1 /usr/share/man/man1/lex.1
}

# 8.17. Tcl-8.6.17
pkg_tcl() {
    unpack 'tcl*-src.tar.*'

    SRCDIR=$(pwd)
    cd unix
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --disable-rpath

    make

    sed -e "s|$SRCDIR/unix|/usr/lib|" \
        -e "s|$SRCDIR|/usr/include|"  \
        -i tclConfig.sh

    sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|"     \
        -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|"  \
        -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|"             \
        -i pkgs/tdbc1.1.12/tdbcConfig.sh

    sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
        -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|"            \
        -i pkgs/itcl4.3.4/itclConfig.sh

    unset SRCDIR

    if want_tests; then
        LC_ALL=C.UTF-8 make test
    fi

    make install 
    chmod 644 /usr/lib/libtclstub8.6.a

    chmod -v u+w /usr/lib/libtcl8.6.so

    make install-private-headers

    ln -sfv tclsh8.6 /usr/bin/tclsh

    mv /usr/share/man/man3/{Thread,Tcl_Thread}.3

    cd ..
    tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1
    mkdir -v -p /usr/share/doc/tcl-8.6.17
    cp -v -r  ./html/* /usr/share/doc/tcl-8.6.17
}

# 8.18. Expect-5.45.4
pkg_expect() {
    unpack 'expect[0-9]*.tar.*'

    python3 -c 'from pty import spawn; spawn(["echo", "ok"])'

    tar -C tclconfig -xf ../autoconf-2.72.tar.xz --strip-components=2 \
        autoconf-2.72/build-aux/config.{guess,sub}

    patch -Np1 -i ../expect-5.45.4-gcc15-1.patch

    ./configure --prefix=/usr           \
                --with-tcl=/usr/lib     \
                --enable-shared         \
                --disable-rpath         \
                --mandir=/usr/share/man \
                --with-tclinclude=/usr/include

    make

    if want_tests; then
        make test
    fi

    make install
    ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
}

# 8.19. DejaGNU-1.6.3
pkg_dejagnu() {
    unpack 'dejagnu-*.tar.*'

    mkdir -v build
    cd       build

    ../configure --prefix=/usr
    makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
    makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi

    if want_tests; then
        make check
    fi

    make install
    install -v -dm755  /usr/share/doc/dejagnu-1.6.3
    install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
}

# 8.20. Pkgconf-2.5.1
pkg_pkgconf() {
    unpack 'pkgconf-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/pkgconf-2.5.1

    make

    make install

    ln -sv pkgconf   /usr/bin/pkg-config
    ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
}

# 8.21. Binutils-2.45
pkg_binutils() {
    unpack 'binutils-*.tar.*'

    mkdir -v build
    cd       build

    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-ld=default \
                 --enable-plugins    \
                 --enable-shared     \
                 --disable-werror    \
                 --enable-64-bit-bfd \
                 --enable-new-dtags  \
                 --with-system-zlib  \
                 --enable-default-hash-style=gnu

    make tooldir=/usr

    if want_tests; then
        make -k check

        grep '^FAIL:' $(find -name '*.log')
    fi

    make tooldir=/usr install

    rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
            /usr/share/doc/gprofng/
}

# 8.22. GMP-6.3.0
pkg_gmp() {
    unpack 'gmp-*.tar.*'

    sed -i '/long long t1;/,+1s/()/(...)/' configure

    ./configure --prefix=/usr    \
                --enable-cxx     \
                --disable-static \
                --docdir=/usr/share/doc/gmp-6.3.0

    make
    make html

    if want_tests; then
        make check 2>&1 | tee gmp-check-log

        awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
    fi

    make install
    make install-html
}

# 8.23. MPFR-4.2.2
pkg_mpfr() {
    unpack 'mpfr-*.tar.*'

    ./configure --prefix=/usr        \
                --disable-static     \
                --enable-thread-safe \
                --docdir=/usr/share/doc/mpfr-4.2.2

    make
    make html

    if want_tests; then
        make check
    fi

    make install
    make install-html
}

# 8.24. MPC-1.3.1
pkg_mpc() {
    unpack 'mpc-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/mpc-1.3.1

    make
    make html

    if want_tests; then
        make check
    fi

    make install
    make install-html
}

# 8.25. Attr-2.5.2
pkg_attr() {
    unpack 'attr-*.tar.*'

    ./configure --prefix=/usr     \
                --disable-static  \
                --sysconfdir=/etc \
                --docdir=/usr/share/doc/attr-2.5.2

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.26. Acl-2.3.2
pkg_acl() {
    unpack 'acl-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/acl-2.3.2

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.27. Libcap-2.76
pkg_libcap() {
    unpack 'libcap-*.tar.*'

    sed -i '/install -m.*STA/d' libcap/Makefile

    make prefix=/usr lib=lib

    if want_tests; then
        make test
    fi

    make prefix=/usr lib=lib install
}

# 8.28. Libxcrypt-4.4.38
pkg_libxcrypt() {
    unpack 'libxcrypt-*.tar.*'

    ./configure --prefix=/usr                \
                --enable-hashes=strong,glibc \
                --enable-obsolete-api=no     \
                --disable-static             \
                --disable-failure-tokens

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.29. Shadow-4.18.0
pkg_shadow() {
    unpack 'shadow-*.tar.*'

    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;

    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:'                   \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
        -i etc/login.defs

    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc   \
                --disable-static    \
                --with-{b,yes}crypt \
                --without-libbsd    \
                --with-group-name-max-length=32

    make

    make exec_prefix=/usr install
    make -C man install-man

    pwconv

    grpconv

    mkdir -p /etc/default
    useradd -D --gid 999

    sed -i '/MAIL/s/yes/no/' /etc/default/useradd

    # COURSE: the book prompts for a password; we take LFS_ROOT_PASSWORD.
    # CHANGE IT after first boot with: passwd root
    echo "root:$LFS_ROOT_PASSWORD" | chpasswd
}

# 8.30. GCC-15.2.0
pkg_gcc() {
    unpack 'gcc-*.tar.*'

    sed -e '/lp64=/s/lib64/lib/' \
        -i.orig gcc/config/aarch64/t-aarch64-linux

    mkdir -v build
    cd       build

    ../configure --prefix=/usr            \
                 LD=ld                    \
                 --enable-languages=c,c++ \
                 --enable-default-pie     \
                 --enable-default-ssp     \
                 --enable-host-pie        \
                 --disable-multilib       \
                 --disable-bootstrap      \
                 --disable-fixincludes    \
                 --with-system-zlib

    make

    if want_tests; then
        ulimit -s -H unlimited

        sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp

        chown -R tester .
        su tester -c "PATH=$PATH make -k check"

        ../contrib/test_summary
    fi

    make install

    chown -v -R root:root \
        /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}

    ln -svr /usr/bin/cpp /usr/lib

    ln -sv gcc.1 /usr/share/man/man1/cc.1

    ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so \
            /usr/lib/bfd-plugins/

    sanity_check <<'LFS_SANITY_EOF'
echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
LFS_SANITY_EOF

    sanity_check <<'LFS_SANITY_EOF'
grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
LFS_SANITY_EOF

    sanity_check <<'LFS_SANITY_EOF'
grep -B4 '^ /usr/include' dummy.log
LFS_SANITY_EOF

    sanity_check <<'LFS_SANITY_EOF'
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
LFS_SANITY_EOF

    sanity_check <<'LFS_SANITY_EOF'
grep "/lib.*/libc.so.6 " dummy.log
LFS_SANITY_EOF

    sanity_check <<'LFS_SANITY_EOF'
grep found dummy.log
LFS_SANITY_EOF

    rm -fv a.out dummy.log

    mkdir -pv /usr/share/gdb/auto-load/usr/lib
    mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
}

# 8.31. Ncurses-6.5-20250809
pkg_ncurses() {
    unpack 'ncurses-*.t*'

    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --with-shared           \
                --without-debug         \
                --without-normal        \
                --with-cxx-shared       \
                --enable-pc-files       \
                --with-pkg-config-libdir=/usr/lib/pkgconfig

    make

    make DESTDIR=$PWD/dest install
    sed -e 's/^#if.*XOPEN.*$/#if 1/' \
        -i dest/usr/include/curses.h
    cp --remove-destination -av dest/* /

    for lib in ncurses form panel menu ; do
        ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
        ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
    done

    ln -sfv libncursesw.so /usr/lib/libcurses.so

    cp -v -R doc -T /usr/share/doc/ncurses-6.5-20250809
}

# 8.32. Sed-4.9
pkg_sed() {
    unpack 'sed-*.tar.*'

    ./configure --prefix=/usr

    make
    make html

    if want_tests; then
        chown -R tester .
        su tester -c "PATH=$PATH make check"
    fi

    make install
    install -d -m755           /usr/share/doc/sed-4.9
    install -m644 doc/sed.html /usr/share/doc/sed-4.9
}

# 8.33. Psmisc-23.7
pkg_psmisc() {
    unpack 'psmisc-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.34. Gettext-0.26
pkg_gettext() {
    unpack 'gettext-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/gettext-0.26

    make

    if want_tests; then
        make check
    fi

    make install
    chmod -v 0755 /usr/lib/preloadable_libintl.so
}

# 8.35. Bison-3.8.2
pkg_bison() {
    unpack 'bison-*.tar.*'

    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.36. Grep-3.12
pkg_grep() {
    unpack 'grep-*.tar.*'

    sed -i "s/echo/#echo/" src/egrep.sh

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.37. Bash-5.3
pkg_bash() {
    unpack 'bash-*.tar.*'

    ./configure --prefix=/usr             \
                --without-bash-malloc     \
                --with-installed-readline \
                --docdir=/usr/share/doc/bash-5.3

    make

    if want_tests; then
        chown -R tester .

LC_ALL=C.UTF-8 su -s /usr/bin/expect tester << "EOF"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF
    fi

    make install
}

# 8.38. Libtool-2.5.4
pkg_libtool() {
    unpack 'libtool-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install

    rm -fv /usr/lib/libltdl.a
}

# 8.39. GDBM-1.26
pkg_gdbm() {
    unpack 'gdbm-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --enable-libgdbm-compat

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.40. Gperf-3.3
pkg_gperf() {
    unpack 'gperf-*.tar.*'

    ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.41. Expat-2.7.3
pkg_expat() {
    unpack 'expat-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --docdir=/usr/share/doc/expat-2.7.3

    make

    if want_tests; then
        make check
    fi

    make install

    install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.7.3
}

# 8.42. Inetutils-2.6
pkg_inetutils() {
    unpack 'inetutils-*.tar.*'

    sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c

    ./configure --prefix=/usr        \
                --bindir=/usr/bin    \
                --localstatedir=/var \
                --disable-logger     \
                --disable-whois      \
                --disable-rcp        \
                --disable-rexec      \
                --disable-rlogin     \
                --disable-rsh        \
                --disable-servers

    make

    if want_tests; then
        make check
    fi

    make install

    mv -v /usr/{,s}bin/ifconfig
}

# 8.43. Less-685
pkg_less() {
    unpack 'less-*.tar.*'

    ./configure --prefix=/usr --sysconfdir=/etc

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.44. Perl-5.42.0
pkg_perl() {
    unpack 'perl-*.tar.*'

    export BUILD_ZLIB=False
    export BUILD_BZIP2=0

    sh Configure -des                                          \
                 -D prefix=/usr                                \
                 -D vendorprefix=/usr                          \
                 -D privlib=/usr/lib/perl5/5.42/core_perl      \
                 -D archlib=/usr/lib/perl5/5.42/core_perl      \
                 -D sitelib=/usr/lib/perl5/5.42/site_perl      \
                 -D sitearch=/usr/lib/perl5/5.42/site_perl     \
                 -D vendorlib=/usr/lib/perl5/5.42/vendor_perl  \
                 -D vendorarch=/usr/lib/perl5/5.42/vendor_perl \
                 -D man1dir=/usr/share/man/man1                \
                 -D man3dir=/usr/share/man/man3                \
                 -D pager="/usr/bin/less -isR"                 \
                 -D useshrplib                                 \
                 -D usethreads

    make

    if want_tests; then
        TEST_JOBS=$(nproc) make test_harness
    fi

    make install
    unset BUILD_ZLIB BUILD_BZIP2
}

# 8.45. XML::Parser-2.47
pkg_xml_parser() {
    unpack 'XML-Parser-*.tar.*'

    perl Makefile.PL

    make

    if want_tests; then
        make test
    fi

    make install
}

# 8.46. Intltool-0.51.0
pkg_intltool() {
    unpack 'intltool-*.tar.*'

    sed -i 's:\\\${:\\\$\\{:' intltool-update.in

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
    install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
}

# 8.47. Autoconf-2.72
pkg_autoconf() {
    unpack 'autoconf-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.48. Automake-1.18.1
pkg_automake() {
    unpack 'automake-*.tar.*'

    ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1

    make

    if want_tests; then
        make -j$(($(nproc)>4?$(nproc):4)) check
    fi

    make install
}

# 8.49. OpenSSL-3.6.0
pkg_openssl() {
    unpack 'openssl-*.tar.*'

    ./config --prefix=/usr         \
             --openssldir=/etc/ssl \
             --libdir=lib          \
             shared                \
             zlib-dynamic

    make

    if want_tests; then
        HARNESS_JOBS=$(nproc) make test
    fi

    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make MANSUFFIX=ssl install

    mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.6.0

    cp -vfr doc/* /usr/share/doc/openssl-3.6.0
}

# 8.50. Libelf from Elfutils-0.193
pkg_libelf() {
    unpack 'elfutils-*.tar.*'

    ./configure --prefix=/usr        \
                --disable-debuginfod \
                --enable-libdebuginfod=dummy

    make

    if want_tests; then
        make -k check
    fi

    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm /usr/lib/libelf.a
}

# 8.51. Libffi-3.5.2
pkg_libffi() {
    unpack 'libffi-*.tar.*'

    ./configure --prefix=/usr    \
                --disable-static \
                --with-gcc-arch=native

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.52. Sqlite-3500400
pkg_sqlite() {
    unpack 'sqlite-autoconf-*.tar.*'

    tar -xf ../sqlite-doc-3500400.tar.xz

    ./configure --prefix=/usr    \
                --disable-static  \
                --enable-fts{4,5} \
                CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                          -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                          -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                          -D SQLITE_SECURE_DELETE=1"

    make LDFLAGS.rpath=""

    make install

    install -v -m755 -d /usr/share/doc/sqlite-3.50.4
    cp -v -R sqlite-doc-3500400/* /usr/share/doc/sqlite-3.50.4
}

# 8.53. Python-3.14.0
pkg_python() {
    unpack 'Python-*.tar.*'

    ./configure --prefix=/usr          \
                --enable-shared        \
                --with-system-expat    \
                --enable-optimizations \
                --without-static-libpython

    make

    if want_tests; then
        make test TESTOPTS="--timeout 120"
    fi

    make install

cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF

    install -v -dm755 /usr/share/doc/python-3.14.0/html

    tar --strip-components=1  \
        --no-same-owner       \
        --no-same-permissions \
        -C /usr/share/doc/python-3.14.0/html \
        -xvf ../python-3.14.0-docs-html.tar.bz2
}

# 8.54. Flit-Core-3.12.0
pkg_flit_core() {
    unpack 'flit_core-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist flit_core
}

# 8.55. Packaging-25.0
pkg_packaging() {
    unpack 'packaging-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist packaging
}

# 8.56. Wheel-0.46.1
pkg_wheel() {
    unpack 'wheel-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist wheel
}

# 8.57. Setuptools-80.9.0
pkg_setuptools() {
    unpack 'setuptools-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist setuptools
}

# 8.58. Ninja-1.13.1
pkg_ninja() {
    unpack 'ninja-*.tar.*'

    sed -i '/int Guess/a \
      int   j = 0;\
      char* jobs = getenv( "NINJAJOBS" );\
      if ( jobs != NULL ) j = atoi( jobs );\
      if ( j > 0 ) return j;\
    ' src/ninja.cc

    python3 configure.py --bootstrap --verbose

    install -vm755 ninja /usr/bin/
    install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
    install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
}

# 8.59. Meson-1.9.1
pkg_meson() {
    unpack 'meson-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist meson
    install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
    install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
}

# 8.60. Kmod-34.2
pkg_kmod() {
    unpack 'kmod-*.tar.*'

    mkdir -p build
    cd       build

    meson setup --prefix=/usr ..    \
                --buildtype=release \
                -D manpages=false

    ninja

    ninja install
}

# 8.61. Coreutils-9.8 or 9.10 (I went ahead to 9.10, 9.11 does not require the patch below, this automation will fail at this point, you are free to choose how to continue - this is supposed to be the sole break in this script)
pkg_coreutils() {
    unpack 'coreutils-*.tar.*'

    patch -Np1 -i ../coreutils-9.10-i18n-1.patch

    autoreconf -fv
    automake -af
    FORCE_UNSAFE_CONFIGURE=1 ./configure \
                --prefix=/usr

    make

    if want_tests; then
        make NON_ROOT_USERNAME=tester check-root

        groupadd -g 102 dummy -U tester

        chown -R tester .

        su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" \
           < /dev/null

        groupdel dummy
    fi

    make install

    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}

# 8.62. Diffutils-3.12
pkg_diffutils() {
    unpack 'diffutils-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.63. Gawk-5.3.2
pkg_gawk() {
    unpack 'gawk-*.tar.*'

    sed -i 's/extras//' Makefile.in

    ./configure --prefix=/usr

    make

    if want_tests; then
        chown -R tester .
        su tester -c "PATH=$PATH make check"
    fi

    rm -f /usr/bin/gawk-5.3.2
    make install

    ln -sv gawk.1 /usr/share/man/man1/awk.1

    install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.3.2
}

# 8.64. Findutils-4.10.0
pkg_findutils() {
    unpack 'findutils-*.tar.*'

    ./configure --prefix=/usr --localstatedir=/var/lib/locate

    make

    if want_tests; then
        chown -R tester .
        su tester -c "PATH=$PATH make check"
    fi

    make install
}

# 8.65. Groff-1.23.0
pkg_groff() {
    unpack 'groff-*.tar.*'

    # COURSE: the book asks you to fill in <paper_size>; LFS_PAPER_SIZE does it.
    PAGE=$LFS_PAPER_SIZE ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.66. GRUB-2.12
pkg_grub() {
    unpack 'grub-*.tar.*'

    echo depends bli part_gpt > grub-core/extra_deps.lst

    ./configure --prefix=/usr     \
                --sysconfdir=/etc \
                --disable-efiemu  \
                --disable-werror

    make

    make install
    mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
}

# 8.67. Gzip-1.14
pkg_gzip() {
    unpack 'gzip-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.68. IPRoute2-6.17.0
pkg_iproute2() {
    unpack 'iproute2-*.tar.*'

    sed -i /ARPD/d Makefile
    rm -fv man/man8/arpd.8

    make NETNS_RUN_DIR=/run/netns

    make SBINDIR=/usr/sbin install

    install -vDm644 COPYING README* -t /usr/share/doc/iproute2-6.17.0
}

# 8.69. Kbd-2.9.0
pkg_kbd() {
    unpack 'kbd-*.tar.*'

    patch -Np1 -i ../kbd-2.9.0-backspace-1.patch

    ./configure --prefix=/usr --disable-vlock

    make

    make install

    cp -R -v docs/doc -T /usr/share/doc/kbd-2.9.0
}

# 8.70. Libpipeline-1.5.8
pkg_libpipeline() {
    unpack 'libpipeline-*.tar.*'

    ./configure --prefix=/usr

    make

    make install
}

# 8.71. Make-4.4.1
pkg_make() {
    unpack 'make-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        chown -R tester .
        su tester -c "PATH=$PATH make check"
    fi

    make install
}

# 8.72. Patch-2.8
pkg_patch() {
    unpack 'patch-*.tar.*'

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.73. Tar-1.35
pkg_tar() {
    unpack 'tar-*.tar.*'

    FORCE_UNSAFE_CONFIGURE=1  \
    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install
    make -C doc install-html docdir=/usr/share/doc/tar-1.35
}

# 8.74. Texinfo-7.2
pkg_texinfo() {
    unpack 'texinfo-*.tar.*'

    sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm

    ./configure --prefix=/usr

    make

    if want_tests; then
        make check
    fi

    make install

    make TEXMF=/usr/share/texmf install-tex

    pushd /usr/share/info
      rm -v dir
      for f in *
        do install-info $f dir 2>/dev/null
      done
    popd
}

# 8.75. Vim-9.1.1806
pkg_vim() {
    unpack 'vim-*.tar.*'

    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h

    ./configure --prefix=/usr

    make

    if want_tests; then
        chown -R tester .
        sed '/test_plugin_glvs/d' -i src/testdir/Make_all.mak

        su tester -c "TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test" \
           &> vim-test.log
    fi

    make install

    ln -sv vim /usr/bin/vi
    for L in  /usr/share/man/{,*/}man1/vim.1; do
        ln -sv vim.1 $(dirname $L)/vi.1
    done

    ln -sv ../vim/vim91/doc /usr/share/doc/vim-9.1.1806

cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
}

# 8.76. MarkupSafe-3.0.3
pkg_markupsafe() {
    unpack 'markupsafe-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist Markupsafe
}

# 8.77. Jinja2-3.1.6
pkg_jinja2() {
    unpack 'jinja2-*.tar.*'

    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

    pip3 install --no-index --find-links dist Jinja2
}

# 8.78. Udev from Systemd-258.1
pkg_udev() {
    unpack 'systemd-[0-9]*.tar.*'

    sed -e 's/GROUP="render"/GROUP="video"/' \
        -e 's/GROUP="sgx", //'               \
        -i rules.d/50-udev-default.rules.in

    sed -i '/systemd-sysctl/s/^/#/' rules.d/99-systemd.rules.in

    sed -e '/NETWORK_DIRS/s/systemd/udev/' \
        -i src/libsystemd/sd-network/network-util.h

    mkdir -p build
    cd       build

    meson setup ..                  \
          --prefix=/usr             \
          --buildtype=release       \
          -D mode=release           \
          -D dev-kvm-mode=0660      \
          -D link-udev-shared=false \
          -D logind=false           \
          -D vconsole=false

    export udev_helpers=$(grep "'name' :" ../src/udev/meson.build | \
                          awk '{print $3}' | tr -d ",'" | grep -v 'udevadm')

    ninja udevadm systemd-hwdb                                           \
          $(ninja -n | grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*') \
          $(realpath libudev.so --relative-to .)                         \
          $udev_helpers

    install -vm755 -d {/usr/lib,/etc}/udev/{hwdb.d,rules.d,network}
    install -vm755 -d /usr/{lib,share}/pkgconfig
    install -vm755 udevadm                             /usr/bin/
    install -vm755 systemd-hwdb                        /usr/bin/udev-hwdb
    ln      -svfn  ../bin/udevadm                      /usr/sbin/udevd
    cp      -av    libudev.so{,*[0-9]}                 /usr/lib/
    install -vm644 ../src/libudev/libudev.h            /usr/include/
    install -vm644 src/libudev/*.pc                    /usr/lib/pkgconfig/
    install -vm644 src/udev/*.pc                       /usr/share/pkgconfig/
    install -vm644 ../src/udev/udev.conf               /etc/udev/
    install -vm644 rules.d/* ../rules.d/README         /usr/lib/udev/rules.d/
    install -vm644 $(find ../rules.d/*.rules \
                          -not -name '*power-switch*') /usr/lib/udev/rules.d/
    install -vm644 hwdb.d/*  ../hwdb.d/{*.hwdb,README} /usr/lib/udev/hwdb.d/
    install -vm755 $udev_helpers                       /usr/lib/udev
    install -vm644 ../network/99-default.link          /usr/lib/udev/network

    tar -xvf ../../udev-lfs-20230818.tar.xz
    make -f udev-lfs-20230818/Makefile.lfs install

    tar -xf ../../systemd-man-pages-258.1.tar.xz                            \
        --no-same-owner --strip-components=1                              \
        -C /usr/share/man --wildcards '*/udev*' '*/libudev*'              \
                                      '*/systemd.link.5'                  \
                                      '*/systemd-'{hwdb,udevd.service}.8

    sed 's|systemd/network|udev/network|'                                 \
        /usr/share/man/man5/systemd.link.5                                \
      > /usr/share/man/man5/udev.link.5

    sed 's/systemd\(\\\?-\)/udev\1/' /usr/share/man/man8/systemd-hwdb.8   \
                                   > /usr/share/man/man8/udev-hwdb.8

    sed 's|lib.*udevd|sbin/udevd|'                                        \
        /usr/share/man/man8/systemd-udevd.service.8                       \
      > /usr/share/man/man8/udevd.8

    rm /usr/share/man/man*/systemd*

    unset udev_helpers

    udev-hwdb update
}

# 8.79. Man-DB-2.13.1
pkg_man_db() {
    unpack 'man-db-*.tar.*'

    ./configure --prefix=/usr                         \
                --docdir=/usr/share/doc/man-db-2.13.1 \
                --sysconfdir=/etc                     \
                --disable-setuid                      \
                --enable-cache-owner=bin              \
                --with-browser=/usr/bin/lynx          \
                --with-vgrind=/usr/bin/vgrind         \
                --with-grap=/usr/bin/grap             \
                --with-systemdtmpfilesdir=            \
                --with-systemdsystemunitdir=

    make

    if want_tests; then
        make check
    fi

    make install
}

# 8.80. Procps-ng-4.0.5
pkg_procps_ng() {
    unpack 'procps-ng-*.tar.*'

    ./configure --prefix=/usr                           \
                --docdir=/usr/share/doc/procps-ng-4.0.5 \
                --disable-static                        \
                --disable-kill                          \
                --enable-watch8bit

    make

    if want_tests; then
        chown -R tester .
        su tester -c "PATH=$PATH make check"
    fi

    make install
}

# 8.81. Util-linux-2.41.2
pkg_util_linux() {
    unpack 'util-linux-*.tar.*'

    ./configure --bindir=/usr/bin     \
                --libdir=/usr/lib     \
                --runstatedir=/run    \
                --sbindir=/usr/sbin   \
                --disable-chfn-chsh   \
                --disable-login       \
                --disable-nologin     \
                --disable-su          \
                --disable-setpriv     \
                --disable-runuser     \
                --disable-pylibmount  \
                --disable-liblastlog2 \
                --disable-static      \
                --without-python      \
                --without-systemd     \
                --without-systemdsystemunitdir        \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir=/usr/share/doc/util-linux-2.41.2

    make

    touch /etc/fstab

    if want_tests; then
        chown -R tester .
        su tester -c "make -k check"
    fi

    make install
}

# 8.82. E2fsprogs-1.47.3
pkg_e2fsprogs() {
    unpack 'e2fsprogs-*.tar.*'

    mkdir -v build
    cd       build

    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-elf-shlibs \
                 --disable-libblkid  \
                 --disable-libuuid   \
                 --disable-uuidd     \
                 --disable-fsck

    make

    if want_tests; then
        make check
    fi

    make install

    rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a

    gunzip -v /usr/share/info/libext2fs.info.gz
    install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info

    makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
    install -v -m644 doc/com_err.info /usr/share/info
    install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info

    sed 's/metadata_csum_seed,//' -i /etc/mke2fs.conf
}

# 8.83. Sysklogd-2.7.2
pkg_sysklogd() {
    unpack 'sysklogd-*.tar.*'

    ./configure --prefix=/usr      \
                --sysconfdir=/etc  \
                --runstatedir=/run \
                --without-logger   \
                --disable-static   \
                --docdir=/usr/share/doc/sysklogd-2.7.2

    make

    make install

cat > /etc/syslog.conf << "EOF"
# Begin /etc/syslog.conf

auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *

# Do not open any internet ports.
secure_mode 2

# End /etc/syslog.conf
EOF
}

# 8.84. SysVinit-3.14
pkg_sysvinit() {
    unpack 'sysvinit-*.tar.*'

    patch -Np1 -i ../sysvinit-3.14-consolidated-1.patch

    make

    make install
}

# ==============================================================================
# 8.86. Stripping   (off unless LFS_STRIP=1 - see deviation 7)
# ==============================================================================
# The book's version of this hardcodes the exact soname of every library it
# wants to protect (libstdc++.so.6.0.34 and friends).  Those change with every
# book revision, and a missing file under `set -e` would kill the run right at
# the finish line, so the loops below tolerate a name that is not there.
do_stripping() {
    say "8.86. Stripping debugging symbols"

    save_usrlib="$(cd /usr/lib; ls ld-linux*[^g])
                 libc.so.6
                 libthread_db.so.1
                 libquadmath.so.0.0.0
                 libstdc++.so.6.0.34
                 libitm.so.1.0.0
                 libatomic.so.1.2.0"

    cd /usr/lib

    for LIB in $save_usrlib; do
        [ -f "/usr/lib/$LIB" ] || { warn "strip: no /usr/lib/$LIB, skipping"; continue; }
        objcopy --only-keep-debug --compress-debug-sections=zstd $LIB $LIB.dbg
        cp $LIB /tmp/$LIB
        strip --strip-debug /tmp/$LIB
        objcopy --add-gnu-debuglink=$LIB.dbg /tmp/$LIB
        install -vm755 /tmp/$LIB /usr/lib
        rm /tmp/$LIB
    done

    online_usrbin="bash find strip"
    online_usrlib="libbfd-2.45.so
                   libsframe.so.2.0.0
                   libhistory.so.8.3
                   libncursesw.so.6.5
                   libm.so.6
                   libreadline.so.8.3
                   libz.so.1.3.1
                   libzstd.so.1.5.7
                   $(cd /usr/lib; find libnss*.so* -type f)"

    for BIN in $online_usrbin; do
        [ -f "/usr/bin/$BIN" ] || { warn "strip: no /usr/bin/$BIN, skipping"; continue; }
        cp /usr/bin/$BIN /tmp/$BIN
        strip --strip-debug /tmp/$BIN
        install -vm755 /tmp/$BIN /usr/bin
        rm /tmp/$BIN
    done

    for LIB in $online_usrlib; do
        [ -f "/usr/lib/$LIB" ] || { warn "strip: no /usr/lib/$LIB, skipping"; continue; }
        cp /usr/lib/$LIB /tmp/$LIB
        strip --strip-debug /tmp/$LIB
        install -vm755 /tmp/$LIB /usr/lib
        rm /tmp/$LIB
    done

    for i in $(find /usr/lib -type f -name \*.so* ! -name \*dbg) \
             $(find /usr/lib -type f -name \*.a)                 \
             $(find /usr/{bin,sbin,libexec} -type f); do
        case "$online_usrbin $online_usrlib $save_usrlib" in
            *$(basename $i)* )
                ;;
            * ) strip --strip-debug $i
                ;;
        esac
    done

    unset BIN LIB save_usrlib online_usrbin online_usrlib
}

# ==============================================================================
# 8.87. Cleaning Up
# ==============================================================================
do_cleanup() {
    say "8.87. Cleaning up"

    rm -rf /tmp/{*,.*}

    find /usr/lib /usr/libexec -name \*.la -delete

    find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf

    # COURSE: the book deletes the tester account here.  If you re-run this
    # script with LFS_RUN_TESTS=1 afterwards you will need to recreate it
    # (see Chapter 7.12 in the book).
    userdel -r tester
}

# ==============================================================================
# driver
# ==============================================================================

preflight() {
    [ "$(id -u)" -eq 0 ] || die "run this as root (you should already be, inside the chroot)"

    # Cheapest reliable "am I in the chroot?" test: the chroot has no /etc/lsb-release
    # or /etc/os-release yet, but it does have /tools or the phase-3 layout, and its
    # root inode differs from the host's.  The book's own marker is simplest: the
    # host has an /etc/passwd with many users; ours has the six from phase 3.
    [ -d "$SOURCES" ] || die "no $SOURCES directory.
    You are almost certainly NOT inside the chroot.  Re-read
    course_QEMU_setup_phase4.sh, do the mounts and the chroot, then run this
    from the (lfs chroot) prompt."
    [ -e /etc/lfs-release ] || [ ! -e /etc/os-release ] || die "/etc/os-release exists.
    That file does not exist in a fresh LFS chroot, so this looks like your
    HOST system.  Building here would damage the host.  Refusing to run."

    grep -q '^tester:' /etc/passwd || warn "no 'tester' user - phase 3 should have created it.
    Harmless while tests are skipped; required if you set LFS_RUN_TESTS=1."

    mountpoint -q /proc || warn "/proc is not mounted inside the chroot; several packages will fail"
    mountpoint -q /sys  || warn "/sys is not mounted inside the chroot"
    [ -c /dev/null ]    || warn "/dev does not look bind-mounted"

    mkdir -p "$STATEDIR" "$LOGDIR"
}

build_one() {
    local name="$1" fn log start elapsed
    fn="$(fn_for "$name")"
    log="$LOGDIR/$name.log"

    if is_done "$name"; then
        printf '    %-14s already built (stamp in %s)\n' "$name" "$STATEDIR"
        return 0
    fi

    say "building $name    (log: $log)"
    start=$SECONDS
    rm -f "$TOPDIR_FILE"

    # Each package runs in a subshell so its cd's and exported variables cannot
    # leak into the next one.  Output goes to the terminal AND the log.
    #
    # The set +e / PIPESTATUS dance is not decoration.  Bash suppresses errexit
    # inside any command used as a condition - `if ! ( set -e; ... )` looks
    # right and silently runs a failing build to completion.  Keeping the
    # subshell out of a conditional context, and reading its status afterwards,
    # is what actually makes a failed `make` stop the run.
    local rc=0
    set +e
    ( set -e; set -o pipefail; "$fn" ) 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e

    if [ "$rc" -ne 0 ]; then
        # Leave the unpacked tree in place - you will want to look at it.
        die "$name FAILED (exit $rc).  The tail of $log:

$(tail -n 25 "$log")

    The unpacked source tree was left in $SOURCES for you to inspect.
    Fix the problem, then re-run this script: everything before $name is
    stamped done and gets skipped.  To rebuild $name from scratch:
        bash $0 --redo $name"
    fi

    # Reclaim the disk the unpacked tree was using.
    if [ "$LFS_RM_SOURCES" = "1" ] && [ -s "$TOPDIR_FILE" ]; then
        local top; top="$(cat "$TOPDIR_FILE")"
        [ -n "$top" ] && rm -rf "${SOURCES:?}/${top:?}"
    fi

    touch "$(stamp_of "$name")"
    elapsed=$(( SECONDS - start ))
    printf '    %s done in %dm%02ds\n' "$name" $(( elapsed / 60 )) $(( elapsed % 60 ))
}

list_progress() {
    local n=0 d=0
    for p in "${PACKAGES[@]}"; do
        n=$(( n + 1 ))
        if is_done "$p"; then d=$(( d + 1 )); printf '  [x] %s\n' "$p"
        else printf '  [ ] %s\n' "$p"; fi
    done
    printf '\n  %d of %d packages built\n' "$d" "$n"
}

usage() {
    sed -n '2,/^# ===/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

main() {
    local only="" from="" dry=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --list)    preflight; list_progress; exit 0 ;;
            --only)    only="${2:?--only needs a package name}"; shift 2 ;;
            --from)    from="${2:?--from needs a package name}"; shift 2 ;;
            --redo)    rm -f "$(stamp_of "${2:?--redo needs a package name}")"
                       only="$2"; shift 2 ;;
            --dry-run) dry=1; shift ;;
            -h|--help) usage ;;
            *)         die "unknown option '$1' (try --help)" ;;
        esac
    done

    preflight

    local plan=() started=0
    for p in "${PACKAGES[@]}"; do
        if [ -n "$only" ]; then
            [ "$p" = "$only" ] && plan+=( "$p" )
            continue
        fi
        if [ -n "$from" ] && [ "$started" -eq 0 ]; then
            [ "$p" = "$from" ] || continue
            started=1
        fi
        plan+=( "$p" )
    done

    if [ -n "$only" ] && [ "${#plan[@]}" -eq 0 ]; then
        die "no package named '$only' (try --list)"
    fi
    if [ -n "$from" ] && [ "$started" -eq 0 ]; then
        die "no package named '$from' (try --list)"
    fi

    if [ "$dry" -eq 1 ]; then
        say "would build ${#plan[@]} packages:"
        printf '    %s\n' "${plan[@]}"
        exit 0
    fi

    say "LFS Chapter 8, ${#plan[@]} packages queued"
    echo "    tests:      $( want_tests && echo 'ON (book default)' || echo 'SKIPPED (LFS_RUN_TESTS=1 to enable)' )"
    echo "    timezone:   $LFS_TIMEZONE"
    echo "    paper size: $LFS_PAPER_SIZE"
    echo "    logs:       $LOGDIR"
    echo "    this will take several hours - consider running it under screen/tmux"

    local t0=$SECONDS
    for p in "${plan[@]}"; do
        build_one "$p"
    done

    # The chapter-closing sections only make sense on a full run.
    if [ -z "$only" ]; then
        if [ "$LFS_STRIP" = "1" ] && ! is_done "_stripping"; then
            do_stripping 2>&1 | tee "$LOGDIR/_stripping.log"
            touch "$(stamp_of "_stripping")"
        fi
        if [ "$LFS_CLEANUP" = "1" ] && ! is_done "_cleanup"; then
            do_cleanup 2>&1 | tee "$LOGDIR/_cleanup.log"
            touch "$(stamp_of "_cleanup")"
        fi
    fi

    say "Chapter 8 complete in $(( (SECONDS - t0) / 60 )) minutes"
    cat <<EOF
    What you have now: a self-hosting LFS system on the target disk, with no
    remaining dependency on the host toolchain.  What it does NOT have yet:
    bootscripts, /etc/fstab, a kernel, or a bootloader.  That is Chapters 9
    and 10 - and you are doing those by hand.

    Next steps, in order:
      1. exit                          # leave the chroot
      2. unmount the virtual filesystems (the block at the end of
         course_QEMU_setup_phase3.sh) before you reboot or snapshot
      3. snapshot, on the Mac side:
         qemu-img create -f qcow2 -b lfs-target-phase4.qcow2 -F qcow2 lfs-target-phase5.qcow2
      4. Chapter 9, by hand, from course_QEMU_setup_phase5.sh

    Worth reading before you move on: $LOGDIR/gcc.log (the sanity checks near
    the end tell you the new toolchain is pointing at /usr/lib, not the host's
    libraries) and $LOGDIR/glibc.log.
EOF
}

main "$@"
