"""Print the theme list with colour swatches for fzf (24-bit ANSI escapes).

usage: list-swatches.py THEMES_DIR NAME...

One line per theme: "swatch<TAB>name". The swatch is "Aa" in the text colour on the background, an
accent diamond and six dots (red, green, yellow, blue, purple, cyan). theme-switch uses only column 2.
"""

import json
import os
import sys


def rgb(h):
    h = h.lstrip("#")
    return ";".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def bg(h):
    return f"\x1b[48;2;{rgb(h)}m"


def fg(h):
    return f"\x1b[38;2;{rgb(h)}m"


RESET = "\x1b[0m"

themes_dir, names = sys.argv[1], sys.argv[2:]
for n in names:
    d = json.load(open(os.path.join(themes_dir, n, "dms.json")))["dark"]
    kv = {}
    for line in open(os.path.join(themes_dir, n, "kitty.conf"), encoding="utf-8"):
        p = line.split()
        if len(p) >= 2 and p[1].startswith("#") and len(p[1]) == 7:
            kv[p[0]] = p[1]
    base, text = d["surface"], d["surfaceText"]
    chips = "".join(fg(kv.get(f"color{i}", text)) + "●" for i in range(1, 7))
    print(
        f"{bg(base)}{fg(text)} Aa {bg(d['primary'])}{fg(d['primaryText'])} ◆ "
        f"{bg(base)} {chips} {RESET}\t{n}"
    )
