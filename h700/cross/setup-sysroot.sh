#!/bin/bash
# Runs INSIDE the debian:11-slim (amd64) container, with the host's
# cross/sysroot-aarch64 mounted at /sysroot. Populates /sysroot with exactly
# the files owned by the :arm64 dev packages needed to cross-compile ITGmania,
# using dpkg -L per package (never a blanket cp of /usr/include,
# which also holds host amd64 headers on a multiarch system).
set -e

# Debian 11 is end-of-life: its packages live on the frozen archive.
sed -i "s#deb.debian.org#archive.debian.org#" /etc/apt/sources.list
dpkg --add-architecture arm64
apt-get update -qq -o Acquire::Check-Valid-Until=false
apt-get install -y -qq crossbuild-essential-arm64 \
  zlib1g-dev:arm64 libjpeg62-turbo-dev:arm64 libpng-dev:arm64 libpcre2-dev:arm64 \
  libgles2-mesa-dev:arm64 libegl1-mesa-dev:arm64 \
  libogg-dev:arm64 libvorbis-dev:arm64 libbz2-dev:arm64 libglew-dev:arm64 \
  libxrandr-dev:arm64 libasound2-dev:arm64 libmad0-dev:arm64 \
  libudev-dev:arm64 libglu1-mesa-dev:arm64 \
  libsdl2-dev:arm64 >/dev/null
# libsdl2-dev only provides headers + the CMake package to build against: at
# runtime the engine loads the CFW's own libSDL2-2.0.so.0, which is newer than
# Debian 11's 2.0.14, so the ABI requirement is satisfied.

echo "=== arm64 + arch-independent packages installed ==="
# Header-only dependencies (e.g. x11proto-dev, pulled in by libx11-dev) are
# often "Architecture: all", not "arm64" -- missing these caused a silent
# "X11/X.h: No such file or directory" once StepMania's build actually
# exercised those headers, well after this script reported success. Grab
# both classes rather than just ":arm64" packages.
dpkg-query -W -f='${Package} ${Architecture}\n' | grep -E ' (arm64|all)$' | sort | tee /tmp/pkglist.txt

echo "=== copying owned files into /sysroot ==="
# Lay the sysroot out usr-merged (/lib, /bin and /sbin as symlinks into /usr)
# so files listed under either path land in one place, and never copy over a
# path that already exists as a link.
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

# Debian 11's -dev symlinks are absolute (libz.so -> /lib/.../libz.so.1),
# which would point at the build container's own (amd64 or missing) files.
find /sysroot -type l -lname '/*' | while read -r l; do
  ln -sfn "$(realpath -m --relative-to="$(dirname "$l")" "/sysroot$(readlink "$l")")" "$l"
done

# SDL 2.0.14's CMake package hardcodes prefix /usr (the build host's own);
# make it relative to the file so it resolves inside the sysroot.
sed -i 's#^set(prefix "/usr")#set(prefix "${CMAKE_CURRENT_LIST_DIR}/../../../..")#' \
  /sysroot/usr/lib/aarch64-linux-gnu/cmake/SDL2/sdl2-config.cmake

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
