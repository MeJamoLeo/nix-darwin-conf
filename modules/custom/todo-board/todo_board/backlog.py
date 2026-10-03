"""backlog — 倉庫（backlog.md）の見出しブロックの読み書き。

`# Canvas`（機械管理）/ `# Mail`（機械管理）/ `# Dated` / `# Someday` / `# Expired` の見出しごとのブロックに分け、
join で元のバイト列に戻る。Someday は 14 日で `# Expired` へ寄せる。
"""
import os

from .store import backlog_path, read_raw
from .items import infer_past, md, norm_text, ORIGIN, STAMP, TASK_ANY, TASK_OPEN


EXPIRE_DAYS = 14
CANVAS_NOTE = "<!-- machine-managed: rewritten hourly by todo-board sync; edit Dated/Someday instead -->"
DEFAULT_BACKLOG = f"# Canvas\n{CANVAS_NOTE}\n\n# Dated\n\n# Someday\n"
ORDER = ["Canvas", "Mail", "Dated", "Someday", "Expired"]


def load_backlog():
    p = backlog_path()
    return read_raw(p) if os.path.exists(p) else DEFAULT_BACKLOG


def split_blocks(text):
    """見出し `# X` ごとのブロック。先頭の見出し前は name=None。join で元のバイト列に戻る。"""
    blocks = [[None, []]]
    for ln in text.split("\n"):
        if ln.startswith("# "):
            blocks.append([ln[2:].strip(), [ln]])
        else:
            blocks[-1][1].append(ln)
    if not blocks[0][1]:
        blocks.pop(0)
    return blocks


def join_blocks(blocks):
    out = []
    for _, ls in blocks:
        out.extend(ls)
    return "\n".join(out)


def get_block(blocks, name):
    for b in blocks:
        if b[0] == name:
            return b
    return None


def ensure_block(blocks, name):
    b = get_block(blocks, name)
    if b:
        return b
    new = [name, [f"# {name}", ""]]
    rank = ORDER.index(name)
    pos = len(blocks)
    for i, (n, _) in enumerate(blocks):
        if n in ORDER and ORDER.index(n) > rank:
            pos = i
            break
    # 直前ブロックが空行で終わっていないと見出しが詰まる
    if pos > 0 and blocks[pos - 1][1] and blocks[pos - 1][1][-1] != "":
        blocks[pos - 1][1].append("")
    blocks.insert(pos, new)
    return new


def append_line(blocks, name, line):
    b = ensure_block(blocks, name)
    ls = b[1]
    last = 0
    for i, ln in enumerate(ls):
        if ln.strip():
            last = i
    ls.insert(last + 1, line)


def add_someday(blocks, body, d):
    body = STAMP.sub("", body).rstrip()
    if not ORIGIN.search(body):
        body += f" (since {md(d)})"
    key = norm_text(body)
    b = get_block(blocks, "Someday")
    if b:
        for ln in b[1]:
            m = TASK_ANY.match(ln)
            if m and norm_text(m[3]) == key:
                return  # 冪等（途中で落ちた再実行で重複させない）
    append_line(blocks, "Someday", f"- [ ] {body}")


def expire_someday(blocks, today):
    b = get_block(blocks, "Someday")
    if not b:
        return
    keep, gone = [], []
    for ln in b[1]:
        m = TASK_OPEN.match(ln)
        s = ORIGIN.search(m[2]) if m else None
        if s:
            sd = infer_past(int(s[1]), int(s[2]), today)
            if sd and (today - sd).days > EXPIRE_DAYS:
                gone.append(ln)
                continue
        keep.append(ln)
    if gone:
        b[1] = keep
        for ln in gone:
            append_line(blocks, "Expired", ln)
