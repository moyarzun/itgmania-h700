# Bundled libraries

Prebuilt aarch64 libraries in `h700/port/lib/`, shipped in the port's `lib/` folder. They are
loaded through `LD_LIBRARY_PATH` / `SDL_VIDEO_GL_DRIVER` /
`SDL_VIDEO_EGL_DRIVER` set by `ITGMania.sh`.

| File | Project | Version | Taken from | License |
|---|---|---|---|---|
| `libGL.so.1`, `libEGL.so.1` | [gl4es](https://github.com/ptitSeb/gl4es) (OpenGL → GLES2 translation, EGL wrapper) | 1.1.7 (built 2024-07-14) | PortMaster's gl4es build, as shipped in the Stardew Valley port (`ports/stardewvalley/gl4es/`) | MIT (`licenses/gl4es.txt`) |
| `libGLU.so.1.3.1` | Mesa GLU | Debian 12 `libglu1-mesa:arm64` | Debian bookworm package | SGI Free Software License B (`licenses/libglu1-mesa.txt`) |
| `libOpenGL.so.0.0.0`, `libGLdispatch.so.0.0.0` | [libglvnd](https://gitlab.freedesktop.org/glvnd/libglvnd) (needed by libGLU) | Debian 12 `libopengl0:arm64`, `libglvnd0:arm64` | Debian bookworm packages | MIT-style (`licenses/libglvnd.txt`) |

The engine links `libGL.so.1` (legacy target, not GLVND) so every GL call goes
to gl4es. SDL2 itself is not bundled: muOS provides `libSDL2-2.0.so.0` (2.28.x)
with the `mali` video driver.

Not bundled any more: `libjpeg.so.62` (nothing in the engine or these
libraries needs it since ITGmania switched to stb_image).
