"""Symlink wallpapers from many packages into one folder as "<source>-<name>".

usage: collect-wallpapers.py OUT PREFIX=STOREPATH [PREFIX=STOREPATH ...]

- share/backgrounds: take every image.
- KDE share/wallpapers/<name>/contents/images*/: take only the largest resolution (images_dark gets a
  "-dark" suffix), and only for packages with nothing in share/backgrounds (nixos-artwork and Fedora
  ship the same pictures in both).
- Skip logos, screenshots and tiny files.
- .jxl is converted to JPEG with djxl (Qt/DMS may not render it); a .jxl that is really a JPEG is
  symlinked as .jpg.
"""

import os
import re
import subprocess
import sys

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".jxl", ".svg"}
SKIP = re.compile(r"logo|screenshot|icon|thumbnail|preview", re.I)
MIN_BYTES = 20_000


def slug(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._+-]+", "-", s).strip("-")
    return s or "x"


def pixels(name: str) -> int:
    m = re.match(r"(\d+)x(\d+)", name)
    return int(m.group(1)) * int(m.group(2)) if m else 0


def place(out: str, prefix: str, src: str, stem: str, seen: set) -> None:
    ext = os.path.splitext(src)[1].lower()
    name = f"{prefix}-{slug(stem)}"
    base, n = name, 2
    while name in seen:
        name, n = f"{base}-{n}", n + 1
    seen.add(name)
    if ext == ".jxl":
        with open(src, "rb") as fh:
            head = fh.read(2)
        if head == b"\xff\xd8":
            # .jxl extension but JPEG content (budgie-backgrounds).
            os.symlink(src, os.path.join(out, name + ".jpg"))
            return
        # Decoding to PNG would be ~70 MB per image; use JPEG (quality 90).
        r = subprocess.run(["djxl", src, os.path.join(out, name + ".jpg"), "--jpeg_quality=90"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0:
            print(f"skip (djxl failed): {src}", file=sys.stderr)
            seen.discard(name)
    else:
        os.symlink(src, os.path.join(out, name + ext))


def main() -> None:
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    seen: set = set()
    for arg in sys.argv[2:]:
        prefix, root = arg.split("=", 1)
        before = len(seen)
        bg = os.path.join(root, "share", "backgrounds")
        for d, _, files in sorted(os.walk(bg, followlinks=True)):
            for f in sorted(files):
                p = os.path.join(d, f)
                stem, ext = os.path.splitext(f)
                if ext.lower() not in EXTS or SKIP.search(f):
                    continue
                if os.path.getsize(p) < MIN_BYTES:
                    continue
                place(out, prefix, os.path.realpath(p), stem, seen)
        wp = os.path.join(root, "share", "wallpapers")
        if os.path.isdir(wp) and len(seen) == before:
            for w in sorted(os.listdir(wp)):
                for sub, suffix in (("images", ""), ("images_dark", "-dark")):
                    d = os.path.join(wp, w, "contents", sub)
                    if not os.path.isdir(d):
                        continue
                    imgs = [f for f in os.listdir(d)
                            if os.path.splitext(f)[1].lower() in EXTS and not SKIP.search(f)]
                    if not imgs:
                        continue
                    best = max(imgs, key=lambda f: (pixels(f), os.path.getsize(os.path.join(d, f))))
                    place(out, prefix, os.path.realpath(os.path.join(d, best)), w + suffix, seen)


main()
