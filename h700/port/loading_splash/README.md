# ITGmania loading screen (muOS)

ITGmania loads every song (and, for new packs, parses and caches them)
**before** it opens its window. muOS has no X11/GTK, so the engine's own
`LoadingWindow` can't show, and startup is a black screen -- several minutes
after adding packs.

`loading_splash.py` runs alongside the game and draws straight to `/dev/fb0`:

- logo and status (`Starting` → `Looking for packs` → `Loading songs` →
  `Preparing`) with animated dots, so activity is always visible;
- a progress bar and `done / total · current pack`, read from
  `~/.itgmania/Logs/log.txt` (`Loading all N songs…` and
  `Loading /Songs/<pack>/…` lines);
- text in the game's language: `Language=` from `Preferences.ini`; empty
  means English, as the engine does on muOS (it can't detect the system
  language). Spanish and English are included (`STRINGS` in
  `loading_splash.py`); anything else falls back to English.

**Handoff.** When `info.txt` logs `Video renderers:` (right before the engine
opens the display) the bar fills and the status becomes `Preparing`. The
splash stays up while the engine initializes video and loads the theme
(~4 s), redrawing itself if the engine flips framebuffer pages or clears the
screen, and exits at the first `PushScreen:` in `log.txt`, when the `itgmania`
process dies, or on a timeout.

That needs `ForceLogFlush=1` in `Preferences.ini` so the engine writes
`log.txt` line by line and `PushScreen:` arrives in time; `ITGMania.sh` enforces
it on every start (the file uses CRLF line endings). If it is still 0, the
script falls back to exiting at `Video renderers:` so it never fights the
game's first frames. With line-by-line logging the counter also advances
smoothly; it is eased anyway. Measured cost: none (90.4 s vs 90.8 s for a
full uncached library load).

Animation runs at ~60 fps (≈15 % of one core), separate from log polling
(~5 Hz; every frame during the handoff), and writes through an `mmap` of the
visible framebuffer page. The driver accepts `FBIO_WAITFORVSYNC` but returns
immediately, so pacing comes from the timer.

Standard library only: the device has no Pillow, so every pixel is
pre-rendered as raw BGRA.

## Files

| File | Runs on | Purpose |
|---|---|---|
| `build_assets.py` | PC (Pillow + ImageMagick) | generates `assets/` from ITGmania's `Data/logo.svg` |
| `loading_splash.py` | device | the loading screen |
| `assets/` | device | 720x480 background (no text), font atlases, `layout.json` |

`ITGMania.sh` starts it in the background right before the engine. To change
texts' look, colors or positions, regenerate the assets:

```bash
python build_assets.py <itgmania>/Data/logo.svg assets
```
