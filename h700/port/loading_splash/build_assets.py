#!/usr/bin/env python3
"""Pre-render the loading-splash assets on the PC (needs Pillow + ImageMagick).

The device has python3 but no Pillow/numpy, so everything the runtime script
(loading_splash.py) draws is baked here into raw BGRA bytes matching the
device framebuffer (720x480 visible, 32bpp, byte order B,G,R,A):

  bg.raw      full 720x480 frame: background, logo, empty progress-bar track
              (no words: all UI text is drawn at runtime so it can follow
              the game's language)
  font_*.bin  glyph atlases, each glyph pre-composited onto BG so the runtime
              only has to copy byte slices (no per-pixel alpha blending)
  layout.json positions/colors shared with the runtime

Usage: python build_assets.py <logo.svg> <out_dir>
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

W, H = 720, 480
BG = (18, 18, 26)
TRACK = (52, 52, 66)
FILL = (240, 160, 40)
TEXT = (235, 235, 240)
DIM = (140, 140, 155)

BAR = {"x": 110, "y": 318, "w": 500, "h": 14}
STATUS_Y = 262          # big status line ("Cargando canciones...")
DETAIL_Y = 346          # counter + pack name
HINT_Y = 420            # hint line at the bottom (top edge)

FONT_BOLD = "/usr/share/fonts/google-noto/NotoSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"

# ASCII + Latin-1 covers Spanish UI text and most pack names; anything else
# is drawn as '?' at runtime.
CHARSET = "".join(chr(c) for c in range(32, 127)) + "".join(
    chr(c) for c in range(0xA1, 0x100)) + "…"


def bgra(img):
    r, g, b, a = img.convert("RGBA").split()
    return Image.merge("RGBA", (b, g, r, a)).tobytes()


def build_font(path, size, color, out):
    font = ImageFont.truetype(path, size)
    ascent, descent = font.getmetrics()
    h = ascent + descent
    glyphs, blob = {}, bytearray()
    for ch in CHARSET:
        w = max(1, round(font.getlength(ch)))
        im = Image.new("RGB", (w, h), BG)
        ImageDraw.Draw(im).text((0, 0), ch, font=font, fill=color)
        data = bgra(im)
        glyphs[ch] = [len(blob), w]
        blob += data
    with open(out + ".bin", "wb") as f:
        f.write(blob)
    return {"file": os.path.basename(out) + ".bin", "height": h, "glyphs": glyphs}


def main(logo_svg, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        logo_png = os.path.join(tmp, "logo.png")
        subprocess.run(["magick", "-background", "none", "-density", "192", logo_svg,
                        "-resize", "150x150", logo_png], check=True)
        logo = Image.open(logo_png).convert("RGBA")

    frame = Image.new("RGBA", (W, H), BG + (255,))
    frame.alpha_composite(logo, ((W - logo.width) // 2, 70))
    d = ImageDraw.Draw(frame)
    title = ImageFont.truetype(FONT_BOLD, 30)
    d.text((W // 2, 236), "ITGMania", font=title, fill=TEXT, anchor="mm")
    b = BAR
    d.rectangle([b["x"], b["y"], b["x"] + b["w"] - 1, b["y"] + b["h"] - 1], fill=TRACK)
    with open(os.path.join(out_dir, "bg.raw"), "wb") as f:
        f.write(bgra(frame))

    layout = {
        "width": W, "height": H, "bg": BG, "track": TRACK, "fill": FILL,
        "bar": BAR, "status_y": STATUS_Y, "detail_y": DETAIL_Y, "hint_y": HINT_Y,
        "fonts": {
            "status": build_font(FONT_BOLD, 22, TEXT, os.path.join(out_dir, "font_status")),
            "detail": build_font(FONT_REG, 17, DIM, os.path.join(out_dir, "font_detail")),
            "hint": build_font(FONT_REG, 15, DIM, os.path.join(out_dir, "font_hint")),
        },
    }
    with open(os.path.join(out_dir, "layout.json"), "w") as f:
        json.dump(layout, f, ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
