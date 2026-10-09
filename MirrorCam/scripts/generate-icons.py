"""Recreate the included vector-drawn app icons. Requires Pillow only for regeneration."""
from pathlib import Path
from PIL import Image, ImageDraw

destination = Path(__file__).resolve().parents[1] / "MirrorCam/Assets.xcassets/AppIcon.appiconset"
destination.mkdir(parents=True, exist_ok=True)
for size in [40, 58, 60, 80, 87, 120, 180, 1024]:
    scale = 4
    canvas = Image.new("RGB", (size * scale, size * scale), (8, 12, 16))
    draw = ImageDraw.Draw(canvas)
    def rect(coords):
        return tuple(int(v * size * scale) for v in coords)
    mint = (115, 242, 209)
    draw.rounded_rectangle(rect((.15, .28, .85, .76)), radius=int(size * scale * .085), outline=mint, width=max(2, int(size * scale * .035)))
    draw.rounded_rectangle(rect((.32, .21, .57, .31)), radius=int(size * scale * .025), fill=mint)
    draw.ellipse(rect((.34, .36, .66, .68)), outline=mint, width=max(2, int(size * scale * .025)))
    draw.line(rect((.5, .40, .5, .64)), fill=(240, 250, 248), width=max(2, int(size * scale * .018)))
    draw.ellipse(rect((.71, .36, .76, .41)), fill=(240, 250, 248))
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(destination / f"icon-{size}.png")
print("Generated 8 opaque RGB app icons.")
