#!/usr/bin/env python3
"""Build macOS icon assets from the approved CPAMC images (requires Pillow)."""

from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "Resources" / "Icons"
LANCZOS = Image.Resampling.LANCZOS


def app_icon():
    source = Image.open(ICONS / "Sources" / "AppIcon-approved.png").convert("RGBA")
    # Use normal macOS icon margins and transparent corners around the approved tile.
    tile = source.resize((824, 824), LANCZOS)
    mask = Image.new("L", (824 * 4, 824 * 4))
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius=184 * 4, fill=255
    )
    tile.putalpha(mask.resize(tile.size, LANCZOS))
    master = Image.new("RGBA", (1024, 1024))
    master.alpha_composite(tile, (100, 100))
    master.save(ICONS / "AppIcon.png")

    iconset = ICONS / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            master.resize((size * scale, size * scale), LANCZOS).save(
                iconset / f"icon_{size}x{size}{suffix}.png"
            )
    subprocess.run(
        ["iconutil", "-c", "icns", "-o", str(ICONS / "AppIcon.icns"), str(iconset)],
        check=True,
    )
    return master


def menu_icons():
    source = Image.open(ICONS / "Sources" / "MenuBar-generated.png").convert("RGBA")
    # Strip model-generated haze and color. All visible pixels use black RGB;
    # antialiased edges are represented only by alpha for native template tinting.
    mask = source.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    mask = mask.crop(mask.getbbox())
    # Widen the negative-space seam so it survives reduction to 16–18 points.
    mask = mask.filter(ImageFilter.MinFilter(15))
    icons = {}
    for points in (16, 18):
        for scale in (1, 2):
            size = points * scale
            mark = ImageOps.contain(mask, ((points - 2) * scale,) * 2, LANCZOS)
            alpha = Image.new("L", (size, size))
            alpha.paste(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
            icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            icon.putalpha(alpha)
            name = "MenuBarTemplate" if points == 18 else "MenuBar16Template"
            suffix = "@2x" if scale == 2 else ""
            icon.save(ICONS / f"{name}{suffix}.png")
            icons[(points, scale)] = icon
    return icons


def preview(master, icons):
    sheet = Image.new("RGB", (1000, 600), "#F3F4F6")
    draw = ImageDraw.Draw(sheet)
    draw.text((40, 24), "TIMING BOMB / ICONS", fill="#18181B", font_size=24)
    sheet.paste(master.resize((440, 440), LANCZOS), (12, 88),
                master.resize((440, 440), LANCZOS))
    draw.text((125, 535), "App / Dock icon", fill="#3F3F46", font_size=20)
    draw.text((500, 100), "Menu bar / 16pt + 18pt", fill="#18181B", font_size=22)
    for y, color, tint in ((155, "#FFFFFF", "#000000"), (235, "#202124", "#FFFFFF")):
        draw.rounded_rectangle((500, y, 950, y + 56), radius=12, fill=color)
        for points, x in ((16, 525), (18, 570)):
            icon = icons[(points, 2)]
            glyph = Image.new("RGBA", icon.size, tint)
            glyph.putalpha(icon.getchannel("A"))
            sheet.paste(glyph, (x, y + (56 - icon.height) // 2), glyph)
    draw.text((500, 322), "Detail / 6x enlarged", fill="#52525B", font_size=18)
    for x, tint, background in ((525, "#000000", "#FFFFFF"), (725, "#FFFFFF", "#202124")):
        draw.rounded_rectangle((x - 20, 365, x + 140, 525), radius=16, fill=background)
        alpha = icons[(18, 2)].getchannel("A").resize((108, 108), Image.Resampling.NEAREST)
        glyph = Image.new("RGBA", alpha.size, tint)
        glyph.putalpha(alpha)
        sheet.paste(glyph, (x + 5, 390), glyph)
    sheet.save(ICONS / "Preview.png")


if __name__ == "__main__":
    preview(app_icon(), menu_icons())
    print(f"Generated app and template icons in {ICONS}")
