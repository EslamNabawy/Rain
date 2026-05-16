from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
MACOS_ICONSET = (
    ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
)
WINDOWS_RES = ROOT / "windows" / "runner" / "resources"
LINUX_RES = ROOT / "linux" / "runner" / "resources"


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def line_gradient(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    width: int,
    start: tuple[int, int, int],
    end: tuple[int, int, int],
    alpha: int = 255,
) -> None:
    if len(points) < 2:
        return
    for index in range(len(points) - 1):
        t = index / max(1, len(points) - 2)
        color = (*mix(start, end, t), alpha)
        draw.line((points[index], points[index + 1]), fill=color, width=width, joint="curve")


def droplet_points(size: int) -> list[tuple[float, float]]:
    cx = size / 2
    top = (cx, size * 0.14)
    bottom = (cx - size * 0.012, size * 0.84)
    left_c1 = (cx - size * 0.275, size * 0.265)
    left_c2 = (cx - size * 0.36, size * 0.66)
    right_c1 = (cx + size * 0.36, size * 0.66)
    right_c2 = (cx + size * 0.275, size * 0.265)

    def cubic(
        p0: tuple[float, float],
        p1: tuple[float, float],
        p2: tuple[float, float],
        p3: tuple[float, float],
        steps: int,
    ) -> list[tuple[float, float]]:
        points: list[tuple[float, float]] = []
        for step in range(steps + 1):
            t = step / steps
            mt = 1 - t
            x = (
                mt * mt * mt * p0[0]
                + 3 * mt * mt * t * p1[0]
                + 3 * mt * t * t * p2[0]
                + t * t * t * p3[0]
            )
            y = (
                mt * mt * mt * p0[1]
                + 3 * mt * mt * t * p1[1]
                + 3 * mt * t * t * p2[1]
                + t * t * t * p3[1]
            )
            points.append((x, y))
        return points

    left = cubic(top, left_c1, left_c2, bottom, 96)
    right = cubic(bottom, right_c1, right_c2, top, 96)
    return left + right[1:]


def draw_logo(size: int = 1024) -> Image.Image:
    scale = 4
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # Premium dark rounded field with a quiet diagonal gradient.
    bg = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    pixels = bg.load()
    top_left = (6, 18, 26)
    bottom_right = (14, 38, 47)
    for y in range(canvas_size):
        for x in range(canvas_size):
            t = (x * 0.35 + y * 0.65) / canvas_size
            r, g, b = mix(top_left, bottom_right, t)
            pixels[x, y] = (r, g, b, 255)
    mask = rounded_mask(canvas_size, round(canvas_size * 0.22))
    img.alpha_composite(Image.composite(bg, Image.new("RGBA", bg.size), mask))

    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (
            canvas_size * 0.16,
            canvas_size * 0.12,
            canvas_size * 0.84,
            canvas_size * 0.86,
        ),
        outline=(53, 231, 214, 62),
        width=round(canvas_size * 0.01),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(round(canvas_size * 0.018)))
    img.alpha_composite(glow)

    draw = ImageDraw.Draw(img)

    # Fine rain texture, clipped by the icon field.
    rain = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rain_draw = ImageDraw.Draw(rain)
    for x in range(-canvas_size // 4, canvas_size + canvas_size // 4, round(canvas_size * 0.15)):
        rain_draw.line(
            (
                x,
                canvas_size * 0.05,
                x + canvas_size * 0.25,
                canvas_size * 0.92,
            ),
            fill=(139, 219, 248, 58),
            width=round(canvas_size * 0.0038),
        )
    rain.putalpha(Image.composite(rain.getchannel("A"), Image.new("L", img.size), mask))
    img.alpha_composite(rain)

    cyan = (122, 219, 255)
    mint = (45, 216, 186)
    emerald = (52, 211, 153)

    # Outer droplet/shield mark.
    points = droplet_points(canvas_size)
    closed_points = points + [points[1]]
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.line(closed_points, fill=(0, 0, 0, 138), width=round(canvas_size * 0.07), joint="curve")
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(canvas_size * 0.012)))
    img.alpha_composite(shadow)

    draw.line(closed_points, fill=(*cyan, 255), width=round(canvas_size * 0.062), joint="curve")
    draw.line(closed_points, fill=(*mint, 255), width=round(canvas_size * 0.046), joint="curve")
    draw.line(closed_points, fill=(232, 252, 255, 248), width=round(canvas_size * 0.019), joint="curve")
    draw.line(closed_points, fill=(*emerald, 250), width=round(canvas_size * 0.009), joint="curve")

    # Internal P2P constellation: simple, centered, readable at launcher sizes.
    node_positions = [
        (canvas_size * 0.392, canvas_size * 0.562),
        (canvas_size * 0.568, canvas_size * 0.445),
        (canvas_size * 0.638, canvas_size * 0.642),
    ]
    for start, end in [(0, 1), (1, 2), (0, 2)]:
        line_gradient(
            draw,
            [node_positions[start], node_positions[end]],
            round(canvas_size * 0.022),
            cyan,
            mint,
            228,
        )
        draw.line(
            (node_positions[start], node_positions[end]),
            fill=(3, 19, 27, 138),
            width=round(canvas_size * 0.008),
        )

    for index, (x, y) in enumerate(node_positions):
        radius = canvas_size * (0.061 if index != 1 else 0.067)
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=(*mint, 235),
            outline=(139, 241, 255, 230),
            width=round(canvas_size * 0.009),
        )
        inner = radius * 0.54
        draw.ellipse((x - inner, y - inner, x + inner, y + inner), fill=(4, 20, 30, 255))
        core = radius * 0.25
        draw.ellipse((x - core, y - core, x + core, y + core), fill=(*cyan, 255))

    # Small premium glint, kept away from busy text-like detail.
    draw.arc(
        (
            canvas_size * 0.355,
            canvas_size * 0.255,
            canvas_size * 0.525,
            canvas_size * 0.535,
        ),
        188,
        236,
        fill=(245, 255, 255, 210),
        width=round(canvas_size * 0.018),
    )

    return img.resize((size, size), Image.Resampling.LANCZOS)


def save_png(path: Path, size: int, source: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main() -> None:
    logo = draw_logo(1024)
    BRANDING.mkdir(parents=True, exist_ok=True)
    logo.save(BRANDING / "rain_app_icon_1024.png")
    logo.save(BRANDING / "rain_logo_premium_1024.png")

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, icon_size in android_sizes.items():
        save_png(ANDROID_RES / folder / "ic_launcher.png", icon_size, logo)

    for icon_size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(MACOS_ICONSET / f"app_icon_{icon_size}.png", icon_size, logo)

    save_png(LINUX_RES / "app_icon.png", 512, logo)

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    logo.save(
        WINDOWS_RES / "app_icon.ico",
        sizes=[(icon_size, icon_size) for icon_size in ico_sizes],
    )


if __name__ == "__main__":
    main()
