"""テーマ一覧を色見本つきで作る（fzf 用、24bit の ANSI エスケープ）。

usage: list-swatches.py THEMES_DIR NAME...

1 行 = 「見本<TAB>テーマ名」。見本は「地の上に文字色で Aa」「差し色の ◆」
「赤・緑・黄・青・紫・水色の ●」。theme-switch は 2 列目（名前）だけを使う。
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
