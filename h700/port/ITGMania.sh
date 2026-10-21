#!/bin/bash
# PortMaster launcher for ITGmania on Allwinner H700 handhelds (muOS).
# Source and build recipe: https://github.com/<owner>/itgmania-h700 (h700/).

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR=/$directory/ports/itgmania
BINARY=itgmania

cd "$GAMEDIR"
chmod +x "$GAMEDIR/$BINARY"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Graphics: this device has no /dev/dri and no X11/Wayland, only the vendor
# "mali" fbdev+EGL+GLESv2 blob. The engine draws desktop OpenGL through the
# gl4es libGL.so.1/libEGL.so.1 pair shipped in lib/, inside a window created
# by the system SDL2's "mali" video driver.
export LD_LIBRARY_PATH="$GAMEDIR/lib:$LD_LIBRARY_PATH"
export SDL_VIDEO_GL_DRIVER="$GAMEDIR/lib/libGL.so.1"
export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/lib/libEGL.so.1"
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_FB=2

# ALSA on this device routes "default" through PipeWire (/etc/asound.conf),
# whose socket lives at /run/pipewire-0, not the standard
# $XDG_RUNTIME_DIR/pipewire-0 path (there is no /run/user/<uid> at all).
export XDG_RUNTIME_DIR=/run
export PIPEWIRE_RUNTIME_DIR=/run

# Save data lives in ~/.itgmania. On first run (or after a firmware
# reinstall wiped it) seed the settings this device needs: the built-in
# controls (muOS-Keys is DEVICE_JOY10 to the engine), a 16:9 720x405 render
# letterboxed in the 720x480 panel, no joystick auto-mapping, and a
# line-by-line log for the loading screen. Existing values are left alone.
SAVEDIR="$HOME/.itgmania/Save"
mkdir -p "$SAVEDIR"
if ! grep -q "Joy10_" "$SAVEDIR/Keymaps.ini" 2>/dev/null; then
  cp "$GAMEDIR/defaults/Keymaps.ini" "$SAVEDIR/Keymaps.ini"
fi
if [ ! -s "$SAVEDIR/Preferences.ini" ]; then
  cp "$GAMEDIR/defaults/Preferences.ini" "$SAVEDIR/Preferences.ini"
fi

# This board has a hall-effect lid switch that can spuriously read "closed"
# mid-session and suspend the system regardless of what's running. Force it
# to read "open" for the session and restore it on exit.
HALLKEY_PATH="/sys/class/power_supply/axp2202-battery/hallkey"
HALLKEY_OVERRIDE=""
if [ -e "$HALLKEY_PATH" ] && ! mountpoint -q "$HALLKEY_PATH"; then
  HALLKEY_OVERRIDE="$(mktemp)"
  echo 1 > "$HALLKEY_OVERRIDE"
  if mount --bind "$HALLKEY_OVERRIDE" "$HALLKEY_PATH" 2>&1; then
    echo "Overrode hallkey (lid switch) to always report open"
  else
    echo "Could not override hallkey; lid-triggered suspend may still fire"
    rm -f "$HALLKEY_OVERRIDE"
    HALLKEY_OVERRIDE=""
  fi
fi

# The CPU governor defaults to "powersave", which pins every core at its
# minimum frequency (480MHz of a possible 1512MHz) instead of scaling with
# load -- a much bigger framerate cost than anything in the engine. Force
# "performance" for the session and restore the previous governors on exit.
GOVERNOR_PATHS=(/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
ORIGINAL_GOVERNORS=()
if [ -e "${GOVERNOR_PATHS[0]}" ]; then
  for g in "${GOVERNOR_PATHS[@]}"; do
    ORIGINAL_GOVERNORS+=("$(cat "$g" 2>/dev/null)")
    echo performance > "$g" 2>/dev/null
  done
fi

# Gameplay and menus are driven by Keymaps.ini's joystick bindings, not by
# these keys. controls.gptk only exists so ScreenMapControllers (whose cursor
# navigation is hardcoded to the keyboard device) stays usable, and so the
# hotkey can kill the game: gptokeyb2 matches the process name exactly, so it
# must be "itgmania" ($BINARY), not "ITGMania".
$GPTOKEYB2 "$BINARY" -c "./controls.gptk" &

pm_platform_helper "$GAMEDIR/$BINARY"

# Core dumps go to tmpfs: the SD card is exFAT and silently produces 0-byte
# core files.
ulimit -c unlimited
CORE_PATTERN_PATH="/proc/sys/kernel/core_pattern"
ORIGINAL_CORE_PATTERN="$(cat "$CORE_PATTERN_PATH" 2>/dev/null)"
echo "/tmp/itgmania-%e-%p.core" > "$CORE_PATTERN_PATH" 2>/dev/null

# Loading screen: the engine loads/caches every song before it opens its
# window (no LoadingWindow without X11), so startup is otherwise a black
# screen -- minutes long after adding packs. Draws to /dev/fb0 and exits on
# its own once the engine shows its first screen.
# See loading_splash/README.md.
# The splash follows log.txt to know when the engine shows its first screen;
# that only works if the engine writes it line by line.
sed -i "s/^ForceLogFlush=0/ForceLogFlush=1/" "$SAVEDIR/Preferences.ini" 2>/dev/null

python3 "$GAMEDIR/loading_splash/loading_splash.py" &

./$BINARY
echo "ITGmania exited with code $?"

if [ -n "$ORIGINAL_CORE_PATTERN" ]; then
  echo "$ORIGINAL_CORE_PATTERN" > "$CORE_PATTERN_PATH" 2>/dev/null
fi

if [ -n "$HALLKEY_OVERRIDE" ]; then
  while mountpoint -q "$HALLKEY_PATH"; do
    umount -l "$HALLKEY_PATH" 2>/dev/null && echo "Unmounted hallkey override" || break
  done
  rm -f "$HALLKEY_OVERRIDE"
fi

if [ "${#ORIGINAL_GOVERNORS[@]}" -gt 0 ]; then
  for i in "${!GOVERNOR_PATHS[@]}"; do
    [ -n "${ORIGINAL_GOVERNORS[$i]}" ] && echo "${ORIGINAL_GOVERNORS[$i]}" > "${GOVERNOR_PATHS[$i]}" 2>/dev/null
  done
fi

pm_finish
