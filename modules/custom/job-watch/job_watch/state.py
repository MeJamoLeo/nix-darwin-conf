"""state — 既報の id を覚えて「新着だけ」を出す。初回は全件が新着（backfill）になる。"""
import json
import os
from . import config as C


def path():
    return os.path.join(C.BASE_DIR, ".state.json")


def load():
    try:
        with open(path(), encoding="utf-8") as f:
            d = json.load(f)
        d.setdefault("seen", {})
        return d
    except (OSError, ValueError):
        return {"version": 1, "seen": {}}


def save(st):
    os.makedirs(C.BASE_DIR, exist_ok=True)
    tmp = path() + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, path())  # 途中で落ちても壊れた state を残さない


def is_new(st, key):
    return key not in st["seen"]


def mark(st, key, today, cls):
    st["seen"][key] = {"first": str(today), "cls": cls}
