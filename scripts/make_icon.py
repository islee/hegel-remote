"""Generate the hegel-remote app icons into App/Assets.xcassets (iOS + macOS).

Outputs:
- `AppIcon.appiconset`: the default, neutral icon. iOS any/light = Silver Dial, dark = Black Dial (amber dot-matrix
  arc), tinted = grayscale of the light art; plus the macOS sizes (light art on the rounded plate).
- `AppIcon-<MODEL>.appiconset` per entry of `MODELS`: an alternate iOS icon, a rounded-rectangle badge with the model
  name in a 5x7 dot-matrix font of our own (light = black on white, dark = white on black, one amber pixel).
- `DockIcon-{Default,<MODEL>}-{Light,Dark}.imageset`: 1024 px images on the rounded plate that the Mac app loads with
  `NSImage(named:)` to switch its Dock icon at runtime.

No Hegel logo, wordmark or typeface: the model names are descriptive text drawn in our own font.

Usage: python3 -I scripts/make_icon.py   (needs Pillow; output is committed, so this only runs when the art changes)
Adding a model: append it to `MODELS` (glyphs for 0-9, H and V exist), then see README "Adding a model icon".
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

SS = 4  # supersampling factor for anti-aliasing
BASE = 1024
OUT = Path(__file__).resolve().parent.parent / "App" / "Assets.xcassets"


def radial(size: int, inner: tuple, outer: tuple, center: tuple[float, float]) -> Image.Image:
    """Radial gradient from `inner` at `center` (fractions of size) to `outer` at the farthest corner."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    assert px is not None
    cx, cy = center[0] * size, center[1] * size
    maxd = math.hypot(max(cx, size - cx), max(cy, size - cy))
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - cx, y - cy) / maxd)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


# Palette (RGB). Shared by the Silver Dial (light) and Black Dial (dark) artwork.
WHITE = (244, 246, 248)
DIM = (52, 55, 59)
AMBER = (217, 164, 65)
INK = (8, 9, 10)


def disc_mask(s: int, d: float) -> Image.Image:
    m = Image.new("L", (s, s), 0)
    r = d / 2
    ImageDraw.Draw(m).ellipse((s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r), fill=255)
    return m


def dial_artwork(size: int, dark: bool) -> Image.Image:
    """The dial icon at `size` px (drawn at SS× and downsampled): Silver Dial (`dark=False`) or Black Dial.

    Silver: silver ring, white dots, amber centre dot. Black: dark knob ring, amber dot-matrix arc, no centre dot.
    Both sit on the charcoal ground and share the geometry, so light/dark swap in place.
    """
    s = size * SS
    canvas = Image.new("RGB", (s, s), (12, 13, 14))
    # Background: charcoal, slightly lighter at the top-left like the app's black skin.
    canvas.paste(radial(s // 8, (34, 37, 41), (10, 11, 12), (0.3, 0.2)).resize((s, s), Image.Resampling.BICUBIC))

    # Soft shadow under the ring.
    shadow = disc_mask(s, s * 0.76).filter(ImageFilter.GaussianBlur(s * 0.03))
    canvas.paste((0, 0, 0), (0, int(s * 0.02)), shadow)
    ring_colors = ((78, 82, 88), (20, 22, 24)) if dark else ((255, 255, 255), (150, 154, 159))
    ring = radial(s // 8, ring_colors[0], ring_colors[1], (0.33, 0.25)).resize((s, s), Image.Resampling.BICUBIC)
    canvas.paste(ring, (0, 0), disc_mask(s, s * 0.76))
    # Black readout.
    canvas.paste(INK if dark else (8, 9, 10), (0, 0), disc_mask(s, s * 0.50))

    # Dot-matrix volume arc: 270° sweep from lower-left, clockwise; the first 15 of 23 dots lit (all, in amber, in dark).
    d = ImageDraw.Draw(canvas)
    n, lit = 23, 15
    r_arc = s * 0.18
    dot = s * 0.022
    for i in range(n):
        a = math.radians(135 + 270 * i / (n - 1))
        x = s / 2 + r_arc * math.cos(a)
        y = s / 2 + r_arc * math.sin(a)
        if dark:
            color = AMBER if i < lit else DIM
        else:
            color = WHITE if i < lit else DIM
        d.rectangle((x - dot / 2, y - dot / 2, x + dot / 2, y + dot / 2), fill=color)
    if not dark:
        # Amber power-state dot in the centre (the Black skin's accent).
        c = s * 0.03
        d.ellipse((s / 2 - c, s / 2 - c, s / 2 + c, s / 2 + c), fill=AMBER)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def tinted_artwork(size: int) -> Image.Image:
    """iOS "tinted" appearance: monochrome luminance art on a dark ground; the system applies the tint colour."""
    return ImageOps.grayscale(dial_artwork(size, dark=False)).convert("RGB")


# Models that get an alternate icon. Adding one is a one-line change here (plus the app-side data, see README).
MODELS = ["H590"]

# 5x7 dot-matrix glyphs for model names (our own font; not Hegel's wordmark or typeface). 1 = lit.
GLYPHS = {
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}

# Badge geometry, as fractions of the canvas.
FRAME = (0.08, 0.30, 0.92, 0.70)
FRAME_RADIUS = 0.10
FRAME_STROKE = 0.04
PITCH = 0.028
DOT = 0.82  # dot size as a fraction of the pitch


def badge_geometry(model: str) -> tuple[list[tuple[float, float]], tuple[float, float, float, float]]:
    """Centres of the lit dots (canvas fractions) and the amber pixel's box, for a model name centred in the frame."""
    cols = len(model) * 6 - 1
    x0 = 0.5 - cols * PITCH / 2 + PITCH / 2
    y0 = 0.5 - 7 * PITCH / 2 + PITCH / 2
    dots = []
    for k, ch in enumerate(model):
        for row, bits in enumerate(GLYPHS[ch]):
            for col, bit in enumerate(bits):
                if bit == "1":
                    dots.append((x0 + (k * 6 + col) * PITCH, y0 + row * PITCH))
    # Amber pixel: one dot, in the frame's top-right inner corner, clear of the characters.
    half = PITCH * DOT / 2
    cx, cy = FRAME[2] - FRAME_STROKE - 0.035, FRAME[1] + FRAME_STROKE + 0.035
    amber = (cx - half, cy - half, cx + half, cy + half)
    # Guard the "does not touch the characters" rule, and that the text fits inside the frame's inner edge.
    for x, y in dots:
        assert x + half < FRAME[2] - FRAME_STROKE and x - half > FRAME[0] + FRAME_STROKE, f"{model} too wide"
        touches = not (x + half <= amber[0] or x - half >= amber[2] or y + half <= amber[1] or y - half >= amber[3])
        assert not touches, f"amber pixel touches {model}"
    # The pixel's outer corner must lie inside the frame's rounded inner corner.
    r_in = FRAME_RADIUS - FRAME_STROKE
    ccx, ccy = FRAME[2] - FRAME_STROKE - r_in, FRAME[1] + FRAME_STROKE + r_in
    assert math.hypot(amber[2] - ccx, ccy - amber[1]) < r_in, "amber pixel outside the rounded corner"
    return dots, amber


def badge_artwork(size: int, model: str, dark: bool) -> Image.Image:
    """Alternate icon: a rounded-rectangle outline with the model name in dot-matrix. Light = black on white."""
    s = size * SS
    plate, ink = ((0, 0, 0), (255, 255, 255)) if dark else ((255, 255, 255), (0, 0, 0))
    canvas = Image.new("RGB", (s, s), plate)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(
        [FRAME[0] * s, FRAME[1] * s, FRAME[2] * s, FRAME[3] * s],
        radius=FRAME_RADIUS * s, outline=ink, width=round(FRAME_STROKE * s))
    dots, amber = badge_geometry(model)
    half = PITCH * DOT * s / 2
    for x, y in dots:
        d.rectangle((x * s - half, y * s - half, x * s + half, y * s + half), fill=ink)
    d.rectangle([v * s for v in amber], fill=AMBER)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def mac_plate(art: Image.Image) -> Image.Image:
    """macOS icon: `art` inside the standard rounded-rect plate (824/1024 with transparent margin)."""
    size = art.width
    art = art.convert("RGBA")
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    plate = round(size * 824 / 1024)
    off = (size - plate) // 2
    mask = Image.new("L", (plate * SS, plate * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, plate * SS - 1, plate * SS - 1), radius=plate * SS * 0.225, fill=255)
    mask = mask.resize((plate, plate), Image.Resampling.LANCZOS)
    out.paste(art.resize((plate, plate), Image.Resampling.LANCZOS), (off, off), mask)
    return out


def write_json(path: Path, obj: dict) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n")


def reset_dir(path: Path) -> None:
    """Empty a generated directory so a removed file cannot linger (only ever called on our own outputs)."""
    path.mkdir(parents=True, exist_ok=True)
    for f in path.iterdir():
        f.unlink()


INFO = {"author": "xcode", "version": 1}


def ios_entry(filename: str, appearance: str | None = None) -> dict:
    entry: dict = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    if appearance:
        entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
    return entry


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "Contents.json", {"info": INFO})
    count = 0

    # Default icon: iOS light / dark / tinted, plus the macOS sizes (light art on the plate).
    icon_dir = OUT / "AppIcon.appiconset"
    reset_dir(icon_dir)
    dial_artwork(BASE, dark=False).save(icon_dir / "ios-1024.png")
    dial_artwork(BASE, dark=True).save(icon_dir / "ios-1024-dark.png")
    tinted_artwork(BASE).save(icon_dir / "ios-1024-tinted.png")
    images = [
        ios_entry("ios-1024.png"),
        ios_entry("ios-1024-dark.png", "dark"),
        ios_entry("ios-1024-tinted.png", "tinted"),
    ]
    big = mac_plate(dial_artwork(BASE, dark=False))
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"mac-{pt}@{scale}x.png"
            big.resize((px, px), Image.Resampling.LANCZOS).save(icon_dir / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_json(icon_dir / "Contents.json", {"images": images, "info": INFO})
    count += len(images)

    # Alternate icons: one appiconset per model (iOS light + dark; no mac entries).
    for model in MODELS:
        alt_dir = OUT / f"AppIcon-{model}.appiconset"
        reset_dir(alt_dir)
        badge_artwork(BASE, model, dark=False).save(alt_dir / "ios-1024.png")
        badge_artwork(BASE, model, dark=True).save(alt_dir / "ios-1024-dark.png")
        write_json(
            alt_dir / "Contents.json",
            {"images": [ios_entry("ios-1024.png"), ios_entry("ios-1024-dark.png", "dark")], "info": INFO})
        count += 2

    # Dock images for runtime switching on the Mac (NSApp.applicationIconImage), 1024 px on the rounded plate.
    docks = {"Default": (dial_artwork(BASE, False), dial_artwork(BASE, True))}
    for model in MODELS:
        docks[model] = (badge_artwork(BASE, model, False), badge_artwork(BASE, model, True))
    for name, (light, dark) in docks.items():
        for variant, art in (("Light", light), ("Dark", dark)):
            set_dir = OUT / f"DockIcon-{name}-{variant}.imageset"
            reset_dir(set_dir)
            mac_plate(art).save(set_dir / "dock-1024.png")
            write_json(set_dir / "Contents.json", {
                "images": [{"filename": "dock-1024.png", "idiom": "universal"}], "info": INFO})
            count += 1
    print(f"wrote {count} images under {OUT}")


if __name__ == "__main__":
    main()
