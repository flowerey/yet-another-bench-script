#!/bin/bash
set -e

# Activate Holy Build Box lib compiliation environment
source /hbb/activate

set -x 

# remove obsolete CentOS repos
cd /etc/yum.repos.d/
rm CentOS-Base.repo CentOS-SCLo-scl-rh.repo CentOS-SCLo-scl.repo CentOS-fasttrack.repo CentOS-x86_64-kernel.repo

yum install -y yum-plugin-ovl # fix for docker overlay fs
yum install -y xz

# download musl cross compilation toolchain
cd ~
curl -L "https://musl.cc/${CROSS}-cross.tgz" -o "${CROSS}-cross.tgz"
tar xf "${CROSS}-cross.tgz"
# ARM 32-bit: force static libatomic (libtool otherwise resolves -latomic to libatomic.so)
[ "$ARCH" = "arm" ] && rm -f /root/${CROSS}-cross/${CROSS}/lib/libatomic.la /root/${CROSS}-cross/${CROSS}/lib/libatomic.so

# download, compile, and install libaio as static library
cd ~
curl -L http://ftp.de.debian.org/debian/pool/main/liba/libaio/libaio_0.3.113.orig.tar.gz -o "libaio.tar.gz"
tar xf libaio.tar.gz
cd libaio-*/src
CC=/root/${CROSS}-cross/bin/${CROSS}-gcc ENABLE_SHARED=0 make prefix=/hbb_exe install

# Activate Holy Build Box exe compilation environment
source /hbb_exe/activate

# download and compile fio
cd ~
curl -L https://github.com/axboe/fio/archive/fio-3.42.tar.gz -o "fio.tar.gz"
tar xf fio.tar.gz
cd fio-fio*
# musl: sys/prctl.h already defines struct prctl_mm_map + all PR_* constants,
# so including linux/prctl.h too causes a redefinition error
grep -rl '<linux/prctl.h>' --include='*.c' --include='*.h' . | xargs -r sed -i 's|#include <linux/prctl.h>|#include <sys/prctl.h>|'
CC=/root/${CROSS}-cross/bin/${CROSS}-gcc ./configure --disable-native --build-static
# ARM 32-bit fix: 64-bit atomics (__atomic_*_8) need libatomic
[ "$ARCH" = "arm" ] && echo 'LIBS += -latomic' >> Makefile
make

# verify no external shared library links
libcheck fio
# copy fio binary to mounted dir
cp fio "/io/fio_$ARCH"

# download and compile iperf
cd ~
curl -L https://github.com/esnet/iperf/archive/3.21.tar.gz -o "iperf.tar.gz"
tar xf iperf.tar.gz
cd iperf*
CC=/root/${CROSS}-cross/bin/${CROSS}-gcc ./configure --disable-shared --disable-profiling --build x86_64-pc-linux-gnu --host "${HOST}" --with-openssl=no --enable-static-bin
make

# verify no external shared library links
libcheck src/iperf3
# copy iperf binary to mounted dir
cp src/iperf3 "/io/iperf3_$ARCH"
