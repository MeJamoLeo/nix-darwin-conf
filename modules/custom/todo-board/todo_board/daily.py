"""daily — 日次ファイルの構造（ブロック・子）、繰り越し、集計、状態フッタ、`## Done today`、harvest／refresh_today。

★ 日中に機械が日次ファイルへ触るのは「提出済みに [x] ✓canvas」と状態フッタだけ（行の増減はしない）。

★ 1段のネスト（2026-10-02 本人決定）:
  - 子タスク（人が書く。機械は生成しない）は 2 スペース（タブも可・正規化）の `  - [ ] ...`。深い字下げも子（レベル1）として扱う。
  - 繰り越しは「トップレベルのブロック丸ごと」。親か子のどれかが未完なら親＋全子をコピー。
    終わった子は `  - [x] ... (done M/D)`（▶■ は落とす・新しい日の集計に数えない）。前日側は未完の親と子だけ `[>] → M/D`。
  - 見出しの集計 `# Today 10/2   ✓ 3 done · 1h 45m` は、そのファイルの `[x]`（`(done M/D)` と `[>]` を除く）と
    `■hh:mm (Nm)` の所要の合計から毎回作り直す（pick／sync／roll）。nvim が直接書いた分は次の毎時 sync で追いつく。
  - `## Done today`（状態フッタの直上）: 今日提出された Canvas／解決済みメールで、今日のファイルに行が無いものを sync が1回だけ追記する。
"""
import datetime as dt
import os
import re

from .store import day_path, load_state, load_status, read_raw, save_state, write_if_changed
from .items import (
    CHECK_PREFIX,
    DONE_MARK,
    DUR_DONE,
    fmt_hm,
    HEAD_TODAY,
    last_paren,
    MARKER,
    md,
    norm_text,
    STAMP,
    TASK_ANY,
    TASK_OPEN,
    text_hash,
)
from .backlog import add_someday, get_block


DONE_TODAY = "Done today"
STATUS_MARK = "<!-- status -->"


def mail_footer():
    mi = load_status().get("mail")
    if not mi:
        return ""
    if mi.get("state") == "ok":
        d = dt.date.fromisoformat(mi["date"])
        return f" · mail: ok ({mi.get('n', 0)} from {md(d)})"
    if mi.get("last"):
        return f" · mail: no digest since {md(dt.date.fromisoformat(mi['last']))}"
    return " · mail: no digest"


def harvest(text, now):
    """日次ファイルで人が [x] にした Canvas／メール行を .state.json に覚える。

    ✓canvas（機械が閉じた行）と Plan prep（倉庫側で同期済み）は対象外。
    「Check if still submittable:」行の [x] は checked_ids（確認済み＝もう出さない）、それ以外は done_ids。
    """
    st = load_state()
    ts = now.strftime("%Y-%m-%dT%H:%M")
    changed = False
    for ln in text.split("\n"):
        m = TASK_ANY.match(ln)
        if not m or m[2] != "x" or "✓canvas" in m[3] or "Plan prep:" in m[3]:
            continue
        mm = MARKER.search(m[3])
        if not mm or mm[1] not in "aqdm":
            continue
        key = f"{mm[1]}:{mm[2]}"
        bucket = "checked_ids" if CHECK_PREFIX in m[3] else "done_ids"
        if key not in st[bucket]:
            st[bucket][key] = ts
            changed = True
    if changed:
        save_state(st)
    return changed


def harvest_file(path, now):
    if os.path.exists(path):
        harvest(read_raw(path), now)


def footer_line(today):
    return canvas_footer() + mail_footer()


def canvas_footer():
    c = load_status().get("canvas") or {}
    ok_at = c.get("ok_at")
    if c.get("error"):
        last = "never ok"
        if ok_at:
            t = dt.datetime.strptime(ok_at, "%Y-%m-%dT%H:%M")
            last = f"last ok {md(t)} {t:%H:%M}"
        err = re.sub(r"\s+", " ", str(c["error"]))[:80]
        return f"Canvas: FAILED ({last}): {err}"
    if ok_at:
        t = dt.datetime.strptime(ok_at, "%Y-%m-%dT%H:%M")
        return f"Canvas: ok {t:%H:%M}"
    return "Canvas: not fetched yet"


def set_footer(text, line):
    """`<!-- status -->` の次行だけを差し替える（無ければ末尾に足す）。他の行は触らない。"""
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        if ln.strip() == STATUS_MARK:
            if i + 1 < len(lines) and lines[i + 1].startswith("Canvas:"):
                lines[i + 1] = line
            else:
                lines.insert(i + 1, line)
            return "\n".join(lines)
    while lines and lines[-1] == "":
        lines.pop()
    lines += ["", STATUS_MARK, line, ""]
    return "\n".join(lines)


def mark_canvas_done(text, done_ids):
    """今日のファイルで、提出済みになった Canvas 行を [x] ✓canvas にする。行の増減はしない。"""
    out = []
    changed = False
    for ln in text.split("\n"):
        m = TASK_OPEN.match(ln)
        if m:
            mm = MARKER.search(m[2])
            if mm and mm[1] in "aqd" and f"{mm[1]}:{mm[2]}" in done_ids and "Plan prep:" not in m[2]:
                ln = f"{m[1]}- [x] {m[2]} ✓canvas"
                changed = True
        out.append(ln)
    return "\n".join(out), changed


def sync_done(daily_text, blocks):
    """日次で [x] にした Dated 行・試験準備行を倉庫でも [x] にする（再計画を防ぐ）。変更の有無を返す。"""
    done = set()
    for ln in daily_text.split("\n"):
        m = TASK_ANY.match(ln)
        if m and m[2] == "x":
            mm = MARKER.search(m[3])
            if mm:
                done.add(f"{mm[1]}:{mm[2]}")
    if not done:
        return False
    changed = False
    for name in ("Dated", "Canvas"):
        b = get_block(blocks, name)
        if not b:
            continue
        for i, ln in enumerate(b[1]):
            m = TASK_OPEN.match(ln)
            if not m:
                continue
            pm = last_paren(m[2])
            if name == "Canvas" and not (pm and pm[1] == "exam"):
                continue
            mm = MARKER.search(m[2])
            key = f"{mm[1]}:{mm[2]}" if mm else f"h:{text_hash(m[2])}"
            if key in done:
                b[1][i] = f"{m[1]}- [x] {m[2]}"
                changed = True
    return changed


def open_markers(text):
    """テキスト中の未完行（`- [ ]`）のマーカー集合。"""
    out = set()
    for ln in text.split("\n"):
        m = TASK_OPEN.match(ln)
        mm = MARKER.search(m[2]) if m else None
        if mm:
            out.add(f"{mm[1]}:{mm[2]}")
    return out


def tally(text):
    """今日完了した行の (件数, 所要分)。`(done M/D)`（繰り越された完了）と `[>]` は数えない。"""
    n = mins = 0
    for ln in text.split("\n"):
        m = TASK_ANY.match(ln)
        if not m or m[2] != "x" or DONE_MARK.search(m[3]):
            continue
        n += 1
        mins += sum(int(x) for x in DUR_DONE.findall(m[3]))  # 所要の無い行は件数だけ（0分）
    return n, mins


def apply_tally(text):
    """`# Today M/D` 見出しに `   ✓ N done · 1h 45m` を付け直す（0件なら付けない）。"""
    n, mins = tally(text)
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        m = HEAD_TODAY.match(ln)
        if m:
            t = ""
            if n:
                t = f"   ✓ {n} done" + (f" · {fmt_hm(mins)}" if mins else "")
            lines[i] = m[1] + t + m[2]
            break
    return "\n".join(lines)


def add_done_today(text, entries):
    """`## Done today`（状態フッタの直上）へ、今日のファイルに無い完了を `- [x] <label> ✓<tag>` で足す。冪等。"""
    lines = text.split("\n")
    have_m = {f"{a}:{b}" for ln in lines for a, b in MARKER.findall(ln)}
    have_t = {norm_text(m[3]) for m in map(TASK_ANY.match, lines) if m}
    new = []
    for marker, label, tag in entries:
        key = norm_text(label)
        if marker in have_m or key in have_t:
            continue
        have_t.add(key)
        new.append(f"- [x] {label} ✓{tag}")
    if not new:
        return text
    for i, ln in enumerate(lines):
        if ln.strip() == f"## {DONE_TODAY}":
            j = i + 1
            last = i
            while j < len(lines) and not lines[j].startswith("#") and lines[j].strip() != STATUS_MARK:
                if lines[j].strip():
                    last = j
                j += 1
            lines[last + 1:last + 1] = new
            return "\n".join(lines)
    block = [f"## {DONE_TODAY}"] + new + [""]
    for i, ln in enumerate(lines):
        if ln.strip() == STATUS_MARK:
            lines[i:i] = block
            return "\n".join(lines)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines + [""] + block)


def refresh_today(today, done_ids, now=None, done_today=None):
    p = day_path(today)
    if not os.path.exists(p):
        return
    text = read_raw(p)
    harvest(text, now or dt.datetime.now())
    if done_ids:
        text, _ = mark_canvas_done(text, done_ids)
    text = set_footer(text, footer_line(today))
    if done_today:
        text = add_done_today(text, done_today)
    write_if_changed(p, apply_tally(text))


def section_of(line, cur):
    if line.startswith("## "):
        return line[3:].strip()
    if line.startswith("# "):
        return "Today" if line.startswith("# Today") else line[2:].strip()
    return cur


def child_map(lines):
    """{子の行 index: 親の行 index}。親＝字下げ無しのタスク行、子＝その直後に続く字下げ付きのタスク行。

    深い字下げも子（レベル1）として扱う（壊さない）。タスク以外の行（空行含む）でブロックは切れる。
    親の無い字下げ行（孤児）は従来どおり単独のタスクとして扱う。
    """
    out = {}
    parent = None
    for i, ln in enumerate(lines):
        m = TASK_ANY.match(ln)
        if not m:
            parent = None
        elif not m[1]:
            parent = i
        elif parent is not None:
            out[i] = parent
    return out


def child_line(status, text):
    return f"  - [{status}] {text}"  # 字下げは2スペースに正規化（タブ・深い字下げも）


def migrate_inbox_in_place(path, d, blocks):
    """既存の日次ファイル内の `# Inbox` の未完行を倉庫 Someday へ移し、空になった見出しを消す。"""
    text = read_raw(path)
    lines = text.split("\n")
    cur = "Today"
    out = []
    moved = False
    for ln in lines:
        cur = section_of(ln, cur)
        m = TASK_OPEN.match(ln)
        if m and cur == "Inbox":
            add_someday(blocks, m[2], d)
            moved = True
            continue
        out.append(ln)
    if not moved:
        return False
    # 空になった Inbox 見出し（と直後の空行）を除く
    res = []
    i = 0
    while i < len(out):
        if out[i].startswith("# Inbox"):
            j = i + 1
            while j < len(out) and not out[j].startswith("#") and not out[j].strip():
                j += 1
            if j >= len(out) or out[j].startswith("#"):
                i = j
                continue
        res.append(out[i])
        i += 1
    return "\n".join(res)


def carry_children(plines, ch, carried, out, prev, d):
    """子を新しい日へ。未完は `[ ]`（印を落とす）、完了済みは `[x] ... (done M/D)`（▶■ を落とす）。

    前日側は未完の子だけ `[>] ... → M/D`（完了済みの子は触らない）。`[>]` など他の状態の子は持ち越さない。
    """
    for c in ch:
        cm = TASK_ANY.match(plines[c])
        cbody = STAMP.sub("", cm[3]).rstrip()
        if cm[2] == " ":
            carried.append(child_line(" ", cbody))
            out[c] = f"{cm[1]}- [>] {cm[3]} → {md(d)}"
        elif cm[2] == "x":
            if not DONE_MARK.search(cbody):
                cbody += f" (done {md(prev)})"
            carried.append(child_line("x", cbody))
