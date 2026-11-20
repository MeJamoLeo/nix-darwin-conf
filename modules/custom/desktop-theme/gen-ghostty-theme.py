"""Rewrite a kitty theme (.conf) as a Ghostty config (colours only).

usage: gen-ghostty-theme.py KITTY_CONF OUT

Loaded via Ghostty's config-file (modules/custom/desktop-theme/home.nix).
"""

import sys

src, out = sys.argv[1], sys.argv[2]
kv = {}
for line in open(src, encoding="utf-8"):
    p = line.split()
    if len(p) >= 2 and p[1].startswith("#") and len(p[1]) == 7:
        kv[p[0]] = p[1]

lines = []
for i in range(16):
    if f"color{i}" in kv:
        lines.append(f"palette = {i}={kv[f'color{i}']}")
for k_kitty, k_ghostty in (
    ("background", "background"),
    ("foreground", "foreground"),
    ("cursor", "cursor-color"),
    ("cursor_text_color", "cursor-text"),
    ("selection_background", "selection-background"),
    ("selection_foreground", "selection-foreground"),
):
    if k_kitty in kv:
        lines.append(f"{k_ghostty} = {kv[k_kitty]}")
open(out, "w").write("\n".join(lines) + "\n")
