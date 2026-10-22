#!/bin/bash
# Cross-compile ITGmania for Allwinner H700 handhelds running muOS (aarch64).
#
# Everything runs in throwaway debian:11-slim containers (amd64, so the cross
# compiler runs at native speed), so the host only needs podman (or docker:
# CONTAINER=docker ./h700/build.sh).
#
#   1. h700/cross/sysroot-aarch64/ is populated with the :arm64 dev packages
#      the engine links against (first run only; delete it to rebuild).
#   2. The engine is configured with h700/cross/toolchain-aarch64.cmake and
#      built in build-h700/ (override with BUILD_DIR=...).
#
# Output: ./itgmania (stripped aarch64 executable, in the repo root like a
# native ITGmania build). Run git submodule update --init --recursive first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H700="$ROOT/h700"
BUILD="${BUILD_DIR:-$ROOT/build-h700}"
CONTAINER="${CONTAINER:-podman}"
# Debian 11 = glibc 2.31 / GCC 10 (GLIBCXX_3.4.28): old enough for every CFW
# PortMaster targets. It is end-of-life, so packages come from the frozen
# archive.debian.org; CMake >= 3.20 comes from bullseye-backports.
IMAGE="docker.io/library/debian:11-slim"
JOBS="${JOBS:-$(nproc)}"

if [ ! -d "$H700/cross/sysroot-aarch64/usr" ]; then
  echo "=== populating h700/cross/sysroot-aarch64 ==="
  mkdir -p "$H700/cross/sysroot-aarch64"
  "$CONTAINER" run --rm --platform linux/amd64 \
    -v "$H700/cross/sysroot-aarch64:/sysroot:z" \
    -v "$H700/cross/setup-sysroot.sh:/setup-sysroot.sh:z" \
    "$IMAGE" bash /setup-sysroot.sh
fi

mkdir -p "$BUILD"
echo "=== building in $BUILD ==="
"$CONTAINER" run --rm --platform linux/amd64 \
  -v "$ROOT:/src:z" \
  -v "$BUILD:/build:z" \
  -e JOBS="$JOBS" \
  "$IMAGE" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    sed -i "s#deb.debian.org#archive.debian.org#" /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian bullseye-backports main" > /etc/apt/sources.list.d/backports.list
    apt-get update -qq -o Acquire::Check-Valid-Until=false
    apt-get install -y -qq crossbuild-essential-arm64 nasm yasm git pkg-config >/dev/null
    apt-get install -y -qq -t bullseye-backports cmake >/dev/null
    cd /build
    # No X11/GTK/PulseAudio/JACK on muOS; the window comes from SDL2 (mali)
    # and audio from ALSA. The crash handler crashes itself on this hardware.
    cmake -DCMAKE_TOOLCHAIN_FILE=/src/h700/cross/toolchain-aarch64.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DWITH_X11=OFF -DWITH_XRANDR=OFF -DWITH_LIBXTST=OFF -DWITH_XINERAMA=OFF \
      -DWITH_CRASH_HANDLER=OFF -DWITH_SSE2=OFF -DWITH_GTK3=OFF \
      -DWITH_PULSEAUDIO=OFF -DWITH_JACK=OFF -DWITH_PARALLEL_PORT=OFF \
      /src
    cmake --build . -j"$JOBS"
    aarch64-linux-gnu-strip --strip-unneeded /src/itgmania
  '
ls -la "$ROOT/itgmania"
