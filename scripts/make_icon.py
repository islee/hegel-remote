"""Generate the hegel-remote app icon (iOS + macOS) into App/Assets.xcassets/AppIcon.appiconset.

The artwork follows the app's base design ("C · Single Dial"): a silver dial ring around a black readout that shows
a dot-matrix volume arc. No Hegel logo or trademarked artwork.

Usage: python3 scripts/make_icon.py   (needs Pillow; output is committed, so this only runs when the art changes)
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

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


def artwork(size: int) -> Image.Image:
    """Full-bleed square artwork at `size` px (drawn at SS× and downsampled)."""
    s = size * SS
    canvas = Image.new("RGB", (s, s), (12, 13, 14))
    # Background: charcoal, slightly lighter at the top-left like the app's black skin.
    canvas.paste(radial(s // 8, (34, 37, 41), (10, 11, 12), (0.3, 0.2)).resize((s, s), Image.Resampling.BICUBIC))

    def circle_mask(d: float) -> Image.Image:
        m = Image.new("L", (s, s), 0)
        r = d / 2
        ImageDraw.Draw(m).ellipse((s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r), fill=255)
        return m

    # Soft shadow under the ring.
    shadow = circle_mask(s * 0.76).filter(ImageFilter.GaussianBlur(s * 0.03))
    canvas.paste((0, 0, 0), (0, int(s * 0.02)), shadow)
    # Silver ring (radial highlight top-left, as in the Silver skin).
    ring = radial(s // 8, (255, 255, 255), (150, 154, 159), (0.33, 0.25)).resize((s, s), Image.Resampling.BICUBIC)
    canvas.paste(ring, (0, 0), circle_mask(s * 0.76))
    # Black readout.
    canvas.paste((8, 9, 10), (0, 0), circle_mask(s * 0.50))

    # Dot-matrix volume arc: 270° sweep from lower-left, clockwise; the first 15 of 23 dots lit.
    d = ImageDraw.Draw(canvas)
    n, lit = 23, 15
    r_arc = s * 0.18
    dot = s * 0.022
    for i in range(n):
        a = math.radians(135 + 270 * i / (n - 1))
        x = s / 2 + r_arc * math.cos(a)
        y = s / 2 + r_arc * math.sin(a)
        color = (244, 246, 248) if i < lit else (52, 55, 59)
        d.rectangle((x - dot / 2, y - dot / 2, x + dot / 2, y + dot / 2), fill=color)
    # Amber power-state dot in the centre (the Black skin's accent).
    c = s * 0.03
    d.ellipse((s / 2 - c, s / 2 - c, s / 2 + c, s / 2 + c), fill=(217, 164, 65))
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def mac_icon(size: int) -> Image.Image:
    """macOS icon: the artwork inside the standard rounded-rect plate (824/1024 with transparent margin)."""
    art = artwork(size).convert("RGBA")
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    plate = round(size * 824 / 1024)
    off = (size - plate) // 2
    mask = Image.new("L", (plate * SS, plate * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, plate * SS - 1, plate * SS - 1), radius=plate * SS * 0.225, fill=255)
    mask = mask.resize((plate, plate), Image.Resampling.LANCZOS)
    out.paste(art.resize((plate, plate), Image.Resampling.LANCZOS), (off, off), mask)
    return out


def main() -> None:
    icon_dir = OUT / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    images = []
    artwork(BASE).save(icon_dir / "ios-1024.png")
    images.append({"filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})

    big = mac_icon(BASE)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"mac-{pt}@{scale}x.png"
            big.resize((px, px), Image.Resampling.LANCZOS).save(icon_dir / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})

    (icon_dir / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    print(f"wrote {len(images)} images to {icon_dir}")


if __name__ == "__main__":
    main()
