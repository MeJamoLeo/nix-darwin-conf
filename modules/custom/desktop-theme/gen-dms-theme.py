"""kitty のテーマファイルから DMS の自作テーマ（JSON）を作る。

usage: gen-dms-theme.py KITTY_CONF OUT_JSON NAME

kitty のテーマは「地・文字・16 色・枠の色」を持つので、そこから DMS（Material 3 風の
キー）へ写す。差し色（primary）は active_border_color（テーマ作者が選んだ強調色）を使い、
地や文字と同じ色なら color4（青）に落とす。面の段（surfaceContainer*）は地を文字色へ
少しずつ寄せて作る（暗いテーマは明るく、明るいテーマは暗くなる）。
明暗どちらのモードでも同じ色にするため dark / light の両方に同じ値を書く。
"""

import json
import sys


def rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a: str, b: str, t: float) -> str:
    """a を b へ t だけ寄せる。"""
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
