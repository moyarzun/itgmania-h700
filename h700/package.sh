#!/bin/bash
# Assemble the PortMaster package from a built ./itgmania (see h700/build.sh).
#
# Output: h700/dist/itgmania.zip, laid out like a PortMaster port:
#   ITGMania.sh          launcher
#   itgmania/            engine, game data, Simply Love (+ h700 patch),
#                        lib/, loading splash, defaults, licenses/
#
# Only the songs that ship with ITGmania itself (Songs/StepMania 5) are
# included; users add their own packs to itgmania/Songs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H700="$ROOT/h700"
DIST="$H700/dist"
PORT="$DIST/ports"
G="$PORT/itgmania"
SYSROOT="$H700/cross/sysroot-aarch64"

[ -x "$ROOT/itgmania" ] || { echo "no ./itgmania -- run h700/build.sh first" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$G"

cp "$H700/port/ITGMania.sh" "$PORT/"
cp "$ROOT/itgmania" "$G/"
cp "$H700/port/controls.gptk" "$G/"
cp -r "$H700/port/defaults" "$G/"
mkdir -p "$G/loading_splash"
cp -r "$H700/port/loading_splash/"{loading_splash.py,build_assets.py,README.md,assets} "$G/loading_splash/"
# exFAT (the usual SD card filesystem) can't hold symlinks: copy real files,
# once each, under the SONAME the loader asks for.
mkdir -p "$G/lib"
for so in libGL.so.1 libEGL.so.1 libGLU.so.1 libOpenGL.so.0 libGLdispatch.so.0; do
  cp -L "$H700/port/lib/$so" "$G/lib/$so"
done

for d in Announcers BackgroundEffects BackgroundTransitions BGAnimations \
         Characters Courses Data NoteSkins; do
  cp -r "$ROOT/$d" "$G/"
done
mkdir -p "$G/Songs" "$G/Themes"
cp "$ROOT/Songs/instructions.txt" "$G/Songs/"
cp -r "$ROOT/Songs/StepMania 5" "$G/Songs/"
cp -r "$ROOT/Themes/_fallback" "$G/Themes/"

# Simply Love is a submodule: export its pinned commit and apply the h700
# patch outside any git work tree (so git apply works on plain files).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$ROOT/Themes/Simply Love" archive --format=tar HEAD | tar -x -C "$TMP"
git -C "$TMP" apply "$H700/patches/simply-love.patch"
mkdir -p "$G/Themes/Simply Love"
cp -r "$TMP/." "$G/Themes/Simply Love/"
rm -rf "$G/Themes/Simply Love/.github" "$G/Themes/Simply Love/.gitignore"

L="$G/licenses"
mkdir -p "$L"
cp "$ROOT/LICENSE" "$L/ITGmania-LICENSE.txt"
cp "$ROOT/Docs/Licenses.txt" "$L/ITGmania-Licenses.txt"
cp "$ROOT/Themes/Simply Love/LICENSE" "$L/SimplyLove-LICENSE.txt"
# FFmpeg is configured with --enable-gpl --enable-version3 (SetupFfmpeg.cmake).
cp "$ROOT/extern/ffmpeg/LICENSE.md" "$L/FFmpeg-LICENSE.md"
cp "$ROOT/extern/ffmpeg/COPYING.GPLv3" "$L/FFmpeg-COPYING.GPLv3.txt"
cp "$H700/licenses/"*.txt "$L/"
for pkg in libglu1-mesa libopengl0 libglvnd0; do
  src="$SYSROOT/usr/share/doc/$pkg/copyright"
  if [ -f "$src" ]; then cp "$src" "$L/$pkg.txt"; else echo "warning: no $src" >&2; fi
done
cp "$H700/port/LIBRARIES.md" "$L/"

(cd "$PORT" && zip -qr9 "$DIST/itgmania.zip" .)
du -sh "$DIST/itgmania.zip"
