#!/bin/bash
# Grab what a muOS H700 device is showing, over SSH, as a PortMaster
# screenshot: the 720x480 panel letterboxed to 4:3 and scaled to 640x480.
#
#   h700/tools/screenshot.sh root@<device-ip> [out.png] [ssh options...]
#
# Reads the currently panned page of /dev/fb0 (BGRA, 720 px * 4 B stride),
# which is safe to do while the game runs. Needs ImageMagick on the host.
set -euo pipefail

HOST="${1:?usage: $0 user@host [out.png] [ssh options...]}"
OUT="${2:-$(dirname "$0")/../portmaster/screenshot.png}"
shift $(( $# >= 2 ? 2 : 1 ))

RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT
ssh "$@" "$HOST" 'y=$(cut -d, -f2 /sys/class/graphics/fb0/pan); dd if=/dev/fb0 bs=2880 skip="$y" count=480 2>/dev/null' > "$RAW"
[ "$(wc -c < "$RAW")" -eq $((2880 * 480)) ] || { echo "short read from /dev/fb0" >&2; exit 1; }

magick -size 720x480 -depth 8 "bgra:$RAW" -alpha off \
  -background black -gravity center -extent 720x540 -resize 640x480 "$OUT"
echo "$OUT"
