"""Build a custom DMS theme (JSON) from a kitty theme file.

usage: gen-dms-theme.py KITTY_CONF OUT_JSON NAME

A kitty theme has background, foreground, 16 colours and a border colour; they are mapped onto DMS's
Material-3-like keys. primary is active_border_color (the theme author's accent), or color4 (blue) when
that equals the background or foreground. surfaceContainer* steps mix the background toward the foreground.
The same values go into dark and light so both modes look identical.
"""

import json
import sys


def rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a: str, b: str, t: float) -> str:
    """Move a toward b by t."""
    ca, cb = rgb(a), rgb(b)
    return hexc([x + (y - x) * t for x, y in zip(ca, cb)])


def lum(h: str) -> float:
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def main() -> None:
    src, out, name = sys.argv[1:4]
    kv = {}
    for line in open(src, encoding="utf-8"):
        parts = line.split()
        if len(parts) >= 2 and parts[1].startswith("#") and len(parts[1]) == 7:
            kv[parts[0]] = parts[1]
    bg, fg = kv["background"], kv["foreground"]
    c = lambda n, d: kv.get(f"color{n}", d)
    primary = kv.get("active_border_color")
    if not primary or contrast(primary, bg) < 2.0 or primary.lower() in (fg.lower(), bg.lower()):
        primary = c(4, fg)
    on_primary = bg if contrast(bg, primary) >= contrast(fg, primary) else fg
    colors = {
        "primary": primary,
        "primaryText": on_primary,
        "primaryContainer": mix(bg, primary, 0.35),
        "secondary": c(6, primary),
        "surface": bg,
        "surfaceText": fg,
        "surfaceVariant": mix(bg, fg, 0.12),
        "surfaceVariantText": mix(bg, fg, 0.7),
        "surfaceTint": primary,
        "background": bg,
        "backgroundText": fg,
        "outline": mix(bg, fg, 0.4),
        "surfaceContainerLowest": mix(bg, fg, 0.02),
        "surfaceContainerLow": mix(bg, fg, 0.04),
        "surfaceContainer": mix(bg, fg, 0.06),
        "surfaceContainerHigh": mix(bg, fg, 0.09),
        "surfaceContainerHighest": mix(bg, fg, 0.12),
        "error": c(1, "#d95757"),
        "warning": c(3, "#ffb454"),
        "info": c(4, primary),
    }
    json.dump({"name": name, "dark": colors, "light": colors}, open(out, "w"), indent=2)


main()
