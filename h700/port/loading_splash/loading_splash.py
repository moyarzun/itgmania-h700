#!/usr/bin/env python3
"""Loading screen for ITGMania on muOS, drawn straight to /dev/fb0.

ITGMania loads every song (and, for newly added packs, parses and caches
them) *before* it creates its window, and this device has no X11/GTK for
the engine's own LoadingWindow -- so startup is a black screen that can last
minutes after adding packs. Started by ITGMania.sh just before the game, this
script paints a splash, follows the engine's log to show progress, and keeps
it up through the engine's video init until its first screen is pushed.

Stdlib only (the device has no Pillow); every pixel comes pre-rendered from
build_assets.py and is copied as raw BGRA byte slices.

Handoff: info.txt gets "Video renderers:" (written and flushed right before
the engine opens the display). Stopping there left ~3.5 s of black while the
engine cleared the screen and loaded the theme, and cut the bar off before
100%. So from then on the bar is shown full ("Preparing") and the splash keeps
redrawing itself whenever the engine pans to another page or clears it, until
the log shows the first "PushScreen:". That needs ForceLogFlush=1 (set by
ITGMania.sh) so the line arrives in time; it also makes progress continuous.

Stop conditions (whichever comes first):
  - "PushScreen:" in log.txt after the handoff, or HANDOFF_TIMEOUT
  - the itgmania process is gone (crash / quit during loading)
  - it never showed up within START_TIMEOUT, or MAX_RUNTIME elapsed
"""
import fcntl
import json
import math
import mmap
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
LOG_DIR = os.environ.get("SPLASH_LOG_DIR", os.path.expanduser("~/.itgmania/Logs"))
PREFS = os.path.join(os.path.dirname(LOG_DIR), "Save", "Preferences.ini")
FB = os.environ.get("SPLASH_FB", "/dev/fb0")
PROC_NAME = "itgmania"

FPS = 60                # animation rate (panel refresh is ~60 Hz)
LOG_EVERY = FPS // 5    # read the logs every N frames (~5 Hz)
# Fraction of the remaining gap the bar closes per frame; derived from a
# per-second rate so the easing speed doesn't depend on FPS.
EASE = 1 - (1 - 0.12) ** (30 / FPS)
FBIO_WAITFORVSYNC = 0x40044620
START_TIMEOUT = 30
HANDOFF_TIMEOUT = 20
MAX_RUNTIME = 60 * 60

RE_GROUPS = re.compile(r"Loading all (\d+) songs across (\d+) groups")
RE_SONG = re.compile(r": Loading /(?:Additional)?Songs/([^/]+)/")
RE_FOUND = re.compile(r": Found \d+ songs in")


class Screen:
    def __init__(self):
        with open(os.path.join(ASSETS, "layout.json"), encoding="utf-8") as f:
            self.layout = L = json.load(f)
        self.w, self.h = L["width"], L["height"]
        self.bg_px = bytes(L["bg"][::-1]) + b"\xff"
        self.fonts = {}
        for name, spec in L["fonts"].items():
            with open(os.path.join(ASSETS, spec["file"]), "rb") as f:
                spec["blob"] = f.read()
            self.fonts[name] = spec
        try:
            with open("/sys/class/graphics/fb0/stride") as f:
                self.stride = int(f.read())
            with open("/sys/class/graphics/fb0/virtual_size") as f:
                self.vheight = int(f.read().split(",")[1])
        except (OSError, ValueError, IndexError):
            self.stride, self.vheight = self.w * 4, self.h
        self.pan_y = self.read_pan()
        with open(os.path.join(ASSETS, "bg.raw"), "rb") as f:
            self.bg_data = f.read()
        # Pixels that must match bg.raw while the splash is intact: a plain
        # corner and the logo center. If the engine clears or draws over the
        # visible page, they won't.
        self.sentinels = [(y * self.w + x) * 4 for x, y in ((8, 8), (360, 140), (711, 471))]
        # Writing into the mmap'd framebuffer is a plain memcpy per row; the
        # first version did a seek()+write() syscall pair per row per page,
        # which is what made it choppy while the engine's 4 loader threads
        # were busy.
        self.fd = os.open(FB, os.O_RDWR)
        self.mm = mmap.mmap(self.fd, self.stride * self.vheight)
        self.vsync_ok = True

    @staticmethod
    def read_pan():
        try:
            with open("/sys/class/graphics/fb0/pan") as f:
                return int(f.read().split(",")[1])
        except (OSError, ValueError, IndexError):
            return 0

    def intact(self):
        base = self.pan_y * self.stride
        for off in self.sentinels:
            y, x4 = divmod(off, self.w * 4)
            p = base + y * self.stride + x4
            if self.mm[p:p + 3] != self.bg_data[off:off + 3]:
                return False
        return True

    def wait_vsync(self):
        # Not every fbdev driver implements it; fall back to plain timing.
        if self.vsync_ok:
            try:
                fcntl.ioctl(self.fd, FBIO_WAITFORVSYNC, b"\0\0\0\0")
            except OSError:
                self.vsync_ok = False

    def blit_rows(self, x, y, rows, pages=None):
        mm, stride = self.mm, self.stride
        for py in pages if pages is not None else (self.pan_y,):
            off = (py + y) * stride + x * 4
            for row in rows:
                mm[off:off + len(row)] = row
                off += stride

    def background(self, all_pages=False):
        row = self.w * 4
        data = self.bg_data
        rows = [data[i * row:(i + 1) * row] for i in range(self.h)]
        pages = range(0, self.vheight - self.h + 1, self.h) if all_pages else None
        self.blit_rows(0, 0, rows, pages=pages)

    def text(self, font_name, y, s, x0=40, width=None, center_on=None):
        """Draw s centered in [x0, x0+width), clearing the whole strip.

        center_on: center this prefix instead of all of s, so animated
        trailing dots don't make the text jump sideways."""
        font = self.fonts[font_name]
        width = width or self.w - 2 * x0
        glyphs, blob, h = font["glyphs"], font["blob"], font["height"]
        s = "".join(c if c in glyphs else "?" for c in s)
        total = sum(glyphs[c][1] for c in s)
        if total > width:
            ell = glyphs["…"][1]
            while s and total + ell > width:
                total -= glyphs[s[-1]][1]
                s = s[:-1]
            s += "…"
            total += ell
        anchor = sum(glyphs[c][1] for c in center_on if c in glyphs) if center_on else total
        left = max(0, min((width - anchor) // 2, width - total))
        rows = []
        for r in range(h):
            parts = [self.bg_px * left]
            for c in s:
                off, gw = glyphs[c]
                start = off + r * gw * 4
                parts.append(blob[start:start + gw * 4])
            parts.append(self.bg_px * (width - left - total))
            rows.append(b"".join(parts))
        self.blit_rows(x0, y, rows)

    def bar(self, frac, marquee=None):
        L = self.layout
        b = L["bar"]
        fill = bytes(L["fill"][::-1]) + b"\xff"
        track = bytes(L["track"][::-1]) + b"\xff"
        if marquee is not None:
            # Indeterminate: a block at position marquee (0..1) of its sweep.
            seg = b["w"] // 5
            pos = int((b["w"] - seg) * marquee)
            row = track * pos + fill * seg + track * (b["w"] - pos - seg)
        else:
            n = int(b["w"] * max(0.0, min(1.0, frac)))
            row = fill * n + track * (b["w"] - n)
        self.blit_rows(b["x"], b["y"], [row] * b["h"])


class LogFollower:
    def __init__(self, path):
        # Skip whatever the previous session left; the engine truncates or
        # recreates the file on startup, which lines() detects below.
        self.path, self.buf = path, ""
        try:
            st = os.stat(path)
            self.ino, self.pos = st.st_ino, st.st_size
        except OSError:
            self.ino, self.pos = None, 0

    def lines(self):
        try:
            st = os.stat(self.path)
        except OSError:
            return []
        if st.st_ino != self.ino or st.st_size < self.pos:
            self.ino, self.pos, self.buf = st.st_ino, 0, ""
        if st.st_size == self.pos:
            return []
        with open(self.path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(self.pos)
            chunk = f.read()
            self.pos = f.tell()
        self.buf += chunk
        *done, self.buf = self.buf.split("\n")
        return done


def pid_of(name):
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                with open(f"/proc/{d}/comm") as f:
                    if f.read().strip() == name:
                        return int(d)
            except OSError:
                pass
    return None


# UI text per game language (ISO 639-1, as in Preferences.ini "Language=").
STRINGS = {
    "en": {
        "init": "Starting",
        "scan": "Looking for packs",
        "songs": "Loading songs",
        "prep": "Preparing",
        "hint": "New packs are processed only the first time and can take several minutes.",
    },
    "es": {
        "init": "Iniciando",
        "scan": "Buscando packs",
        "songs": "Cargando canciones",
        "prep": "Preparando",
        "hint": "Los packs nuevos se procesan solo la primera vez y pueden tardar varios minutos.",
    },
}


def read_prefs():
    try:
        with open(PREFS, encoding="utf-8", errors="replace") as f:
            return dict(l.strip().split("=", 1) for l in f if "=" in l)
    except OSError:
        return {}


def game_language(prefs):
    # Same choice the engine makes: Language= if set, else the system
    # language -- which it can't detect on muOS ("Unable to determine system
    # language. Using English."), so empty means English. Unknown -> English.
    lang = prefs.get("Language", "").strip().lower()[:2]
    return lang if lang in STRINGS else "en"


def main():
    # Without line-by-line log writes "PushScreen:" could arrive seconds late
    # and the splash would fight the engine's first frames, so only do the
    # handoff when it's on; otherwise stop at "Video renderers:" as before.
    prefs = read_prefs()
    handoff_enabled = prefs.get("ForceLogFlush") == "1"
    T = STRINGS[game_language(prefs)]
    scr = Screen()
    # Every page once, in case the panned page changes under us; after this
    # only the visible page is updated.
    scr.background(all_pages=True)
    L = scr.layout
    bar_w = L["bar"]["w"]

    log = LogFollower(os.path.join(LOG_DIR, "log.txt"))
    info = LogFollower(os.path.join(LOG_DIR, "info.txt"))
    t0 = time.monotonic()
    pid = None
    phase, total, done, group = "init", 0, 0, ""
    shown = 0.0                      # eased bar fraction actually drawn
    last_bar = last_detail = last_status = None
    hint_drawn = False
    handoff_t = None
    frame = 0
    period = 1.0 / FPS
    next_t = time.monotonic()

    while time.monotonic() - t0 < MAX_RUNTIME:
        # During the handoff every frame counts: poll the log each frame.
        if handoff_t is not None or frame % LOG_EVERY == 0:
            if pid is None:
                pid = pid_of(PROC_NAME)
                if pid is None and time.monotonic() - t0 > START_TIMEOUT:
                    return
            elif not os.path.exists(f"/proc/{pid}"):
                return
            if handoff_t is None and any("Video renderers:" in l for l in info.lines()):
                if not handoff_enabled:
                    return
                handoff_t = time.monotonic()
                phase, group, done = "prep", "", total
            if handoff_t is not None and time.monotonic() - handoff_t > HANDOFF_TIMEOUT:
                return
            for line in log.lines():
                if handoff_t is not None and ": PushScreen:" in line:
                    return
                m = RE_SONG.search(line)
                if m:
                    done += 1
                    group = m.group(1)
                    continue
                m = RE_GROUPS.search(line)
                if m:
                    total, phase = int(m.group(1)), "songs"
                elif "Loading songs using" in line:
                    phase = "scan"
                elif RE_FOUND.search(line) or "Loading courses." in line:
                    phase, group, done = "prep", "", total

        t = time.monotonic() - t0
        determinate = bool(total) and phase in ("songs", "prep")
        if determinate:
            # The log is written in buffered chunks, so the real count jumps;
            # ease toward it instead of snapping.
            target = min(1.0, done / total)
            shown += (target - shown) * EASE
            if target - shown < 0.0005:
                shown = target
            bar = ("p", int(bar_w * shown))
        else:
            # Indeterminate: smooth back-and-forth sweep (~1.6 s per pass).
            bar = ("m", round((1 - math.cos(t * math.pi / 1.6)) / 2 * 1000) / 1000)

        status = T[phase] + "." * (int(t * 2.5) % 4)
        if determinate and phase == "songs":
            detail = f"{round(shown * total)} / {total}" + (f"  \u00b7  {group}" if group else "")
        else:
            detail = ""

        scr.wait_vsync()
        pan = scr.read_pan()
        if pan != scr.pan_y:
            # Engine flipped pages: the other page has the background from the
            # initial paint but stale bar/text.
            scr.pan_y = pan
            last_bar = last_status = last_detail = None
            hint_drawn = False
        if not scr.intact():
            # Engine cleared or drew over the visible page: repaint it all.
            scr.background()
            last_bar = last_status = last_detail = None
            hint_drawn = False
        if not hint_drawn:
            scr.text("hint", L["hint_y"], T["hint"], x0=10)
            hint_drawn = True
        if bar != last_bar:
            if bar[0] == "p":
                scr.bar(bar[1] / bar_w)
            else:
                scr.bar(0, marquee=bar[1])
            last_bar = bar
        if status != last_status:
            scr.text("status", L["status_y"], status, center_on=T[phase])
            last_status = status
        if detail != last_detail:
            scr.text("detail", L["detail_y"], detail)
            last_detail = detail

        frame += 1
        next_t += period
        delay = next_t - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        else:
            next_t = time.monotonic()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never let the splash get in the way of the game
        print(f"loading_splash: {e}", file=sys.stderr)
