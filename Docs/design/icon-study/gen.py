"""Generate 14 hegel-remote icon concepts (1024 px, iOS full-bleed) + 64/32 px renders for the icon study."""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
SS = 2
S = 1024 * SS
C = S / 2

WHITE = (244, 246, 248)
DIM = (52, 55, 59)
AMBER = (217, 164, 65)
INK = (8, 9, 10)
CHAR = (18, 20, 22)


def radial(inner, outer, center=(0.33, 0.25), size=S):
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    assert px is not None
    cx, cy = center[0] * small, center[1] * small
    maxd = math.hypot(max(cx, small - cx), max(cy, small - cy))
    for y in range(small):
        for x in range(small):
            t = min(1.0, math.hypot(x - cx, y - cy) / maxd)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img.resize((size, size), Image.Resampling.BICUBIC)


def linear(top, bottom):
    img = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        img.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img.resize((S, S), Image.Resampling.BICUBIC)


def disc(d, cx=C, cy=C):
    m = Image.new("L", (S, S), 0)
    r = d / 2
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def charcoal():
    return radial((34, 37, 41), (10, 11, 12), (0.3, 0.2))


def silver():
    return radial((255, 255, 255), (150, 154, 159))


def dark_knob():
    return radial((78, 82, 88), (20, 22, 24))


def shadow(img, d, dy=0.02):
    img.paste((0, 0, 0), (0, int(S * dy)), disc(d).filter(ImageFilter.GaussianBlur(S * 0.03)))


def sq(draw, x, y, size, color):
    draw.rectangle((x - size / 2, y - size / 2, x + size / 2, y + size / 2), fill=color)


def dot_arc(draw, r, n=23, lit=15, size=0.022, start=135, sweep=270, on=WHITE, off=DIM):
    for i in range(n):
        a = math.radians(start + sweep * i / (n - 1))
        sq(draw, C + r * math.cos(a), C + r * math.sin(a), S * size, on if i < lit else off)


# 5x7 dot-matrix glyphs
GLYPHS = {
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "h": ["10000", "10000", "10110", "11001", "10001", "10001", "10001"],
    "r": ["00000", "00000", "10110", "11001", "10000", "10000", "10000"],
}


def matrix_text(draw, text, cx, cy, pitch, color, dot=0.8):
    w = len(text) * 5 * pitch + (len(text) - 1) * pitch
    x0 = cx - w / 2 + pitch / 2
    y0 = cy - 7 * pitch / 2 + pitch / 2
    for k, ch in enumerate(text):
        for row, bits in enumerate(GLYPHS[ch]):
            for col, b in enumerate(bits):
                if b == "1":
                    sq(draw, x0 + (k * 6 + col) * pitch, y0 + row * pitch, pitch * dot, color)


def save(name, img):
    img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    img.save(OUT / f"{name}.png")
    for px in (180, 64, 32):
        img.resize((px, px), Image.Resampling.LANCZOS).save(OUT / f"{name}-{px}.png")


def i01_silver_dial():
    img = charcoal(); shadow(img, S * 0.76)
    img.paste(silver(), (0, 0), disc(S * 0.76)); img.paste(INK, (0, 0), disc(S * 0.50))
    d = ImageDraw.Draw(img); dot_arc(d, S * 0.18)
    d.ellipse((C - S * 0.03, C - S * 0.03, C + S * 0.03, C + S * 0.03), fill=AMBER)
    return img


def i02_black_dial():
    img = charcoal(); shadow(img, S * 0.76)
    img.paste(dark_knob(), (0, 0), disc(S * 0.76)); img.paste(INK, (0, 0), disc(S * 0.50))
    d = ImageDraw.Draw(img); dot_arc(d, S * 0.18, on=AMBER)
    return img


def i03_oled_digits():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img); matrix_text(d, "39", C, C, S * 0.07, WHITE)
    return img


def i04_front_panel():
    img = linear((40, 43, 47), (14, 15, 17))
    img.paste((0, 0, 0), (0, int(S * 0.01)), disc(S * 0.3, C, S * 0.72).filter(ImageFilter.GaussianBlur(S * 0.02)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((S * 0.1, S * 0.28, S * 0.9, S * 0.5), radius=S * 0.03, fill=INK)
    matrix_text(d, "39", S * 0.72, S * 0.39, S * 0.022, WHITE)
    for k in range(4):
        sq(d, S * (0.2 + k * 0.07), S * 0.39, S * 0.035, WHITE if k < 3 else DIM)
    img.paste(silver(), (0, 0), disc(S * 0.3, C, S * 0.72))
    d.line((C, S * 0.6, C, S * 0.65), fill=INK, width=int(S * 0.012))
    return img


def i05_click_wheel():
    img = linear((235, 236, 238), (200, 203, 207))
    shadow(img, S * 0.8, 0.015)
    img.paste((250, 251, 252), (0, 0), disc(S * 0.8)); img.paste((214, 217, 221), (0, 0), disc(S * 0.34))
    d = ImageDraw.Draw(img)
    t = S * 0.012
    d.line((S * 0.2, C, S * 0.27, C), fill=(90, 94, 99), width=int(t))
    d.line((S * 0.73, C, S * 0.8, C), fill=(90, 94, 99), width=int(t))
    d.line((S * 0.765, C - S * 0.035, S * 0.765, C + S * 0.035), fill=(90, 94, 99), width=int(t))
    matrix_text(d, "39", C, C, S * 0.022, (20, 21, 22))
    return img


def i06_knob_indicator():
    img = Image.new("RGB", (S, S), CHAR); shadow(img, S * 0.7)
    img.paste(silver(), (0, 0), disc(S * 0.7))
    d = ImageDraw.Draw(img)
    a = math.radians(-60)
    x1, y1 = C + S * 0.22 * math.cos(a), C + S * 0.22 * math.sin(a)
    x2, y2 = C + S * 0.32 * math.cos(a), C + S * 0.32 * math.sin(a)
    d.line((x1, y1, x2, y2), fill=INK, width=int(S * 0.025))
    return img


def i07_level_bars():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)
    cols, rows, pitch = 6, 7, S * 0.09
    x0 = C - (cols - 1) * pitch / 2
    for c in range(cols):
        h = c + 2
        for r in range(rows):
            on = r < h and c < 4
            col = (AMBER if r == h - 1 else WHITE) if on else DIM
            if r < h:
                sq(d, x0 + c * pitch, C + 3 * pitch - r * pitch, pitch * 0.72, col)
    return img


def i08_power_matrix():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)
    r = S * 0.25
    for i in range(26):
        t = math.radians(35 + 290 * i / 25)
        sq(d, C + r * math.sin(t), C - r * math.cos(t), S * 0.04, AMBER)
    for k in range(5):
        sq(d, C, C - S * 0.3 + k * S * 0.055, S * 0.04, AMBER)
    return img


def i09_wave_ring():
    img = charcoal(); shadow(img, S * 0.76)
    img.paste(silver(), (0, 0), disc(S * 0.76)); img.paste(INK, (0, 0), disc(S * 0.54))
    d = ImageDraw.Draw(img)
    n = 15
    for i in range(n):
        x = C - S * 0.2 + i * S * 0.4 / (n - 1)
        amp = math.sin(i / (n - 1) * math.pi) * S * 0.12
        for y in (C - amp * math.sin(i * 1.3) * 0.5,):
            h = max(S * 0.03, abs(amp * (0.4 + 0.6 * abs(math.sin(i * 1.7)))))
            k = int(h / (S * 0.028))
            for j in range(-k, k + 1):
                sq(d, x, C + j * S * 0.028, S * 0.02, WHITE)
    return img


def i10_monogram():
    img = Image.new("RGB", (S, S), CHAR)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((S * 0.16, S * 0.16, S * 0.84, S * 0.84), radius=S * 0.12, fill=INK)
    matrix_text(d, "hr", C, C, S * 0.055, WHITE)
    sq(d, S * 0.74, S * 0.26, S * 0.04, AMBER)
    return img


def i11_cone():
    img = Image.new("RGB", (S, S), CHAR)
    for k, (dd, col) in enumerate([(0.86, (60, 63, 68)), (0.72, (28, 30, 33)), (0.6, (90, 94, 99)), (0.46, (22, 24, 26)),
                                   (0.3, (150, 154, 159)), (0.16, (230, 232, 235))]):
        img.paste(col, (0, 0), disc(S * dd))
    return img


def i12_arc_gauge():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)
    box = (S * 0.18, S * 0.18, S * 0.82, S * 0.82)
    d.arc(box, 135, 405, fill=DIM, width=int(S * 0.06))
    d.arc(box, 135, 315, fill=AMBER, width=int(S * 0.06))
    d.ellipse((C - S * 0.05, C - S * 0.05, C + S * 0.05, C + S * 0.05), fill=WHITE)
    return img


def i13_split():
    img = Image.new("RGB", (S, S), CHAR); shadow(img, S * 0.76)
    full = silver()
    half = Image.new("L", (S, S), 0)
    ImageDraw.Draw(half).rectangle((0, 0, C, S), fill=255)
    m = disc(S * 0.76)
    img.paste(full, (0, 0), Image.composite(m, Image.new("L", (S, S), 0), half))
    right = Image.composite(m, Image.new("L", (S, S), 0), half.point(lambda v: 255 - v))
    img.paste(dark_knob(), (0, 0), right)
    d = ImageDraw.Draw(img)
    d.line((C, S * 0.14, C, S * 0.3), fill=AMBER, width=int(S * 0.024))
    return img


def i14_dot_grid():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)
    n, pitch = 5, S * 0.14
    x0 = C - (n - 1) * pitch / 2
    for r in range(n):
        for c in range(n):
            idx = r * n + c
            d.ellipse((x0 + c * pitch - S * 0.045, x0 + r * pitch - S * 0.045, x0 + c * pitch + S * 0.045,
                       x0 + r * pitch + S * 0.045), fill=WHITE if idx < 16 else (AMBER if idx == 16 else DIM))
    return img


FUNCS = [i01_silver_dial, i02_black_dial, i03_oled_digits, i04_front_panel, i05_click_wheel, i06_knob_indicator,
         i07_level_bars, i08_power_matrix, i09_wave_ring, i10_monogram, i11_cone, i12_arc_gauge, i13_split, i14_dot_grid]

for f in FUNCS:
    save(f.__name__, f())
print(len(FUNCS))
