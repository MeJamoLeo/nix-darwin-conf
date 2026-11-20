"""wofi に出す一覧を、色見本つき（Pango markup）で作る。

usage: list-markup.py THEMES_DIR NAME...

1 行 = 「地の上に文字色で Aa」「差し色」「赤・緑・黄・青・紫・水色」の見本 ＋ テーマ名。
名前は行末の空白区切りの最後の語にする（theme-switch が awk '{print $NF}' で取り出す）。
"""

import json
import os
import sys

themes_dir, names = sys.argv[1], sys.argv[2:]
for n in names:
    d = json.load(open(os.path.join(themes_dir, n, "dms.json")))["dark"]
    kv = {}
    for line in open(os.path.join(themes_dir, n, "kitty.conf"), encoding="utf-8"):
        p = line.split()
        if len(p) >= 2 and p[1].startswith("#") and len(p[1]) == 7:
            kv[p[0]] = p[1]
    bg, fg = d["surface"], d["surfaceText"]
    chips = "".join(
        f'<span foreground="{kv.get(f"color{i}", fg)}">●</span>' for i in range(1, 7)
    )
    print(
        f'<span font_family="monospace">'
        f'<span background="{bg}" foreground="{fg}"> Aa </span>'
        f'<span background="{d["primary"]}" foreground="{d["primaryText"]}"> ◆ </span> '
        f'<span background="{bg}"> {chips} </span>'
        f"</span>   {n}"
    )
