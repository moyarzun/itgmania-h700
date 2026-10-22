#!/bin/bash
# Source and build recipe: https://github.com/moyarzun/itgmania-h700 (h700/).

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

GAMEDIR="/$directory/ports/itgmania"

cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
  source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
  source "${controlfolder}/libgl_default.txt"
fi

if [ "$LIBGL_FB" != "" ] && [ "${CFW_NAME^^}" != "KNULLI" ]; then
  export SDL_VIDEO_GL_DRIVER="$GAMEDIR/gl4es.${DEVICE_ARCH}/libGL.so.1"
  export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/gl4es.${DEVICE_ARCH}/libEGL.so.1"
fi

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

$ESUDO chmod +x "$GAMEDIR/itgmania"

# Settings, profiles and scores live in ~/.itgmania; keep them in the port.
mkdir -p "$GAMEDIR/conf/.itgmania/Save"
[ -f "$GAMEDIR/conf/.itgmania/Save/Preferences.ini" ] || cp "$GAMEDIR/defaults/Preferences.ini" "$GAMEDIR/conf/.itgmania/Save/"
[ -f "$GAMEDIR/conf/.itgmania/Save/Keymaps.ini" ] || cp "$GAMEDIR/defaults/Keymaps.ini" "$GAMEDIR/conf/.itgmania/Save/"
bind_directories ~/.itgmania "$GAMEDIR/conf/.itgmania"

# The theme is laid out for 16:9: render the largest 16:9 area that fits the
# screen (black bars fill the rest).
if [ $((DISPLAY_WIDTH * 9)) -le $((DISPLAY_HEIGHT * 16)) ]; then
  W=$DISPLAY_WIDTH; H=$((DISPLAY_WIDTH * 9 / 16))
else
  W=$((DISPLAY_HEIGHT * 16 / 9)); H=$DISPLAY_HEIGHT
fi
sed -i "s/^DisplayWidth=[0-9]*/DisplayWidth=$W/; s/^DisplayHeight=[0-9]*/DisplayHeight=$H/; s/^DisplayAspectRatio=[0-9.]*/DisplayAspectRatio=1.777778/" "$GAMEDIR/conf/.itgmania/Save/Preferences.ini"

# controls.gptk only drives ScreenMapControllers and the exit hotkey; gameplay
# reads the gamepad through Keymaps.ini.
$GPTOKEYB2 "itgmania" -c "./controls.gptk" &
pm_platform_helper "$GAMEDIR/itgmania"

# Songs load before the game opens its window: show a progress bar from its log
# ("Loading all N songs", then a "Loading /Songs/..." line per song) until it
# starts video ("Video renderers").
LOG="$GAMEDIR/conf/.itgmania/Logs/log.txt"
rm -f "$LOG"
./itgmania &
GAME_PID=$!
PortMasterDialogInit "no-harbour"
PortMasterDialog "messages_begin"
while kill -0 $GAME_PID 2>/dev/null && ! grep -q "Video renderers" "$LOG" 2>/dev/null; do
  TOTAL=$(sed -n 's/.*Loading all \([0-9]*\) songs.*/\1/p' "$LOG" 2>/dev/null)
  LOADED=$(grep -c ": Loading /Songs/" "$LOG" 2>/dev/null)
  PortMasterDialog "progress" "Loading songs" "${LOADED:-0}" "${TOTAL:-100}"
  sleep 1
done
PortMasterDialog "progress_clear"
PortMasterDialogExit
wait $GAME_PID

pm_finish
