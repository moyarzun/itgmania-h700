#!/bin/bash
# Runs INSIDE the debian:12-slim (amd64) container, with the host's
# cross/sysroot-aarch64 mounted at /sysroot. Populates /sysroot with exactly
# the files owned by the :arm64 dev packages needed to cross-compile ITGmania,
# using dpkg -L per package (never a blanket cp of /usr/include,
# which also holds host amd64 headers on a multiarch system).
set -e

dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq crossbuild-essential-arm64 \
  zlib1g-dev:arm64 libjpeg62-turbo-dev:arm64 libpng-dev:arm64 libpcre2-dev:arm64 \
  libgles2-mesa-dev:arm64 libegl1-mesa-dev:arm64 \
  libogg-dev:arm64 libvorbis-dev:arm64 libbz2-dev:arm64 libglew-dev:arm64 \
  libxrandr-dev:arm64 libasound2-dev:arm64 libmad0-dev:arm64 \
  libudev-dev:arm64 libglu1-mesa-dev:arm64 \
  libsdl2-dev:arm64 >/dev/null
# libsdl2-dev only provides headers + the CMake package to build against: at
# runtime the engine loads the device's own libSDL2-2.0.so.0 (muOS ships
# 2.28.x with the "mali" video driver), which is newer than Debian 12's
# 2.26.x, so the ABI requirement is satisfied.

echo "=== arm64 + arch-independent packages installed ==="
# Header-only dependencies (e.g. x11proto-dev, pulled in by libx11-dev) are
# often "Architecture: all", not "arm64" -- missing these caused a silent
# "X11/X.h: No such file or directory" once StepMania's build actually
# exercised those headers, well after this script reported success. Grab
# both classes rather than just ":arm64" packages.
dpkg-query -W -f='${Package} ${Architecture}\n' | grep -E ' (arm64|all)$' | sort | tee /tmp/pkglist.txt

echo "=== copying owned files into /sysroot ==="
# Debian 12 is usr-merged: /lib, /bin and /sbin are symlinks into /usr and
# are listed as owned files. Recreate that layout up front (copying the
# symlinks first would leave them dangling and break every later mkdir -p
# under them), and never copy over a path that already exists as a link.
for d in lib bin sbin; do
  mkdir -p "/sysroot/usr/$d"
  [ -e "/sysroot/$d" ] || ln -s "usr/$d" "/sysroot/$d"
done
while read -r pkg arch; do
  dpkg -L "${pkg}:${arch}" | while read -r f; do
    [ -L "/sysroot$f" ] && continue
    if [ -f "$f" ] || [ -L "$f" ]; then
      mkdir -p "/sysroot$(dirname "$f")"
      cp -a "$f" "/sysroot$f"
    fi
  done
done < /tmp/pkglist.txt

echo "=== sysroot size ==="
du -sh /sysroot

echo "=== link test: zlib ==="
cat > /tmp/z.c << 'EOF'
#include <zlib.h>
#include <stdio.h>
int main(){ printf("zlib version: %s\n", zlibVersion()); return 0; }
EOF
aarch64-linux-gnu-gcc -O2 --sysroot=/sysroot -o /tmp/z /tmp/z.c -lz
file /tmp/z
