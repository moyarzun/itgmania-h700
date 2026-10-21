# ITGmania for H700 handhelds (muOS)

This branch (`h700`) is [ITGmania](https://github.com/itgmania/itgmania)
v1.3.0 with the changes needed to run it on Allwinner H700 handhelds running
[muOS](https://muos.dev) (tested on an Anbernic RG SP), packaged for
[PortMaster](https://portmaster.games). It is published to satisfy the GPLv3:
everything needed to rebuild the distributed binary is here.

## What's different from upstream

Engine (commits on top of `v1.3.0`, see `git log v1.3.0..h700`):

- **SDL2 window backend** (`src/arch/LowLevelWindow/LowLevelWindow_SDL.*`).
  The device has no X11, Wayland or DRM; the only graphics path is the vendor
  Mali fbdev+EGL blob, reached through muOS's SDL2 `mali` video driver, with
  [gl4es](https://github.com/ptitSeb/gl4es) translating desktop GL to GLES2.
- **Cross-compiling** Linux x86_64 → aarch64 (FFmpeg configure, toolchain file
  forwarding to sub-builds, link order).
- **GLSL shader effects skipped** on this backend (gl4es crashes linking them
  on the Mali-G31 driver; they are optional effects).
- **Input**: ignore muOS's virtual "Mouse" evdev device, no automatic keyboard
  mappings (one press must reach the engine once), context-sensitive A/B, a
  protected built-in controls slot in the key-mapping screen.
- **Bug fixes**: ALSA position during XRUN, Course/Nonstop-mode iterator
  crash, a profile leak, movie banners showing their first frame when banner
  animation is off, missing on-screen keyboard assets in `_fallback`.
- **GrooveStats score submission disabled** (handheld scores aren't
  comparable to cabinet scores).

Theme: `patches/simply-love.patch` adapts Simply Love 5.9.0 (the submodule
commit pinned by v1.3.0) to the 720x480 screen (`Scripts/SL-DeviceLayout.lua`
and the screens that use it). It is applied at packaging time.

Port (`port/`): the PortMaster launcher, gptokeyb controls, default
`Keymaps.ini`/`Preferences.ini` seeded on first run, bundled GL libraries
(`port/LIBRARIES.md`) and a loading screen shown while songs load
(`port/loading_splash/`).

## Building

Requirements: git, podman (or docker), ~10 GB of disk. Nothing else on the
host: the cross compiler and target libraries live in containers.

```bash
git clone -b h700 --recurse-submodules https://github.com/<owner>/itgmania-h700.git
cd itgmania-h700
./h700/build.sh      # -> ./itgmania (aarch64)
./h700/package.sh    # -> h700/dist/itgmania.zip
```

`build.sh` first populates `h700/cross/sysroot-aarch64/` with Debian 12
`:arm64` development packages (`h700/cross/setup-sysroot.sh`), then configures
the engine with `h700/cross/toolchain-aarch64.cmake` and these options:

```
-DCMAKE_BUILD_TYPE=Release -DWITH_X11=OFF -DWITH_XRANDR=OFF -DWITH_LIBXTST=OFF
-DWITH_XINERAMA=OFF -DWITH_CRASH_HANDLER=OFF -DWITH_SSE2=OFF -DWITH_GTK3=OFF
-DWITH_PULSEAUDIO=OFF -DWITH_JACK=OFF -DWITH_PARALLEL_PORT=OFF
```

## Installing by hand

Unzip `h700/dist/itgmania.zip` into the SD card's `ports` folder (it contains
`ITGMania.sh` and `itgmania/`), put song packs in `ports/itgmania/Songs/`, and
launch ITGMania from the Ports menu. The first start after adding packs takes
a while (about 90 s for ~1,700 songs); the loading screen shows progress.

## Licenses

ITGmania and Simply Love are GPLv3-or-later; the h700 changes are released
under the same terms (new files keep the permissive StepMania header where
they were derived from it). The package includes every license in
`itgmania/licenses/`. The three songs in `Songs/StepMania 5` are the ones
upstream ITGmania distributes: *Goin' Under* (NegaRen, chart by Fraxtil),
*Mecha-Tribe Assault* and *Springtime* (Kommisar).
