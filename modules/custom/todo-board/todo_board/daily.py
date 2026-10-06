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

from .store import base_dir, day_path, load_state, load_status, read_raw, save_state, write_if_changed
from .items import (
    CHECK_PREFIX,
    wd_md,
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
from .backlog import add_someday, get_block, load_backlog, split_blocks
from .items import parse_item
from .gcal import is_exam_title


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


def calendar_footer():
    c = load_status().get("calendar")
    if not c:
        return ""
    if c.get("state") == "suspicious":
        return " · calendar: suspicious result (kept previous)"
    if c.get("state") == "error":
        err = re.sub(r"\s+", " ", str(c.get("error")))[:60]
        return f" · calendar: FAILED: {err}"
    no = c.get("no_emoji") or 0
    return f" · calendar: ok ({c.get('n', 0)} exams" + (f" · {no} without 📕)" if no else ")")


def blocks_footer(today):
    """blocks が今日のどの行にも紐づけられなかった Claude 作業時間（0 なら出さない）。"""
    b = load_status().get("blocks") or {}
    if b.get("date") == today.isoformat() and b.get("unlinked_min"):
        return f" · Claude time not linked: {fmt_hm(b['unlinked_min'])}"
    return ""


def footer_line(today):
    return canvas_footer() + mail_footer() + calendar_footer() + blocks_footer(today)


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


PREP_PREFIX = "Plan prep:"


def prep_marker_fix(body):
    """旧形式の `Plan prep:` 行（試験本体と同じ ⟨a:ID⟩）を準備専用の ⟨p:ID⟩ に直す。

    準備を [x] にすると試験本体（a:ID）まで閉じた扱いになる混線を避けるため（2026-10-06）。
    """
    if PREP_PREFIX not in body:
        return body
    return re.sub(r"⟨a:([0-9A-Za-z]+)⟩", r"⟨p:\1⟩", body)


def sync_done(daily_text, blocks):
    """日次で [x] にした Dated 行・試験準備行を倉庫でも [x] にする（再計画を防ぐ）。変更の有無を返す。"""
    done = set()
    for ln in daily_text.split("\n"):
        m = TASK_ANY.match(ln)
        if m and m[2] == "x":
            mm = MARKER.search(m[3])
            if mm:
                if PREP_PREFIX in m[3] and mm[1] in "ap":
                    done.add(f"p:{mm[2]}")  # 準備行は p: だけ（旧形式の a:ID で試験本体の行まで閉じない）
                else:
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
            if name == "Canvas" and mm and mm[1] == "a":
                key = f"p:{mm[2]}"  # 旧形式の試験行（a:ID）は準備の印として p: で照合する
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


def prep_fix_text(text):
    """今日のファイルの旧形式の `Plan prep:` 行（⟨a:ID⟩）を ⟨p:ID⟩ に直す（トップレベルの未完・完了行だけ）。"""
    out = []
    for ln in text.split("\n"):
        m = TASK_ANY.match(ln)
        out.append(f"{m[1]}- [{m[2]}] {prep_marker_fix(m[3])}" if m and not m[1] else ln)
    return "\n".join(out)


# ---------------------------------------------------------------- 終わった試験の準備行の失効
EXPIRED = "(expired)"
EXAM_WORD = re.compile(r"(?<![A-Za-z])(midterm|exam|final)s?(?![A-Za-z])|(試験)|(中間)|(期末)", re.I)
COURSE_RE = re.compile(r"(?<![A-Za-z0-9])([A-Za-z]{2,4})[\s._-]?(\d{4})(?![0-9])")


def course_codes(text):
    return {m[1].upper() + m[2] for m in COURSE_RE.finditer(text)}


def exam_words(text):
    """題名の試験語 → 正規化した集合（中間→midterm、期末→final、試験→exam）。"""
    out = set()
    for m in EXAM_WORD.finditer(text):
        w = m[0].lower()
        out.add("midterm" if w.startswith("midterm") or w == "中間" else "final" if w.startswith("final") or w == "期末"
                else "exam")
    return out


def exams_from_blocks(blocks, today):
    """倉庫の Canvas／Mail／Dated から試験項目 [{marker, codes, words, start(datetime), allday}]。"""
    out = []
    for name in ("Canvas", "Mail", "Dated"):
        b = get_block(blocks, name)
        for ln in (b[1] if b else []):
            m = TASK_ANY.match(ln)
            if not m or m[2] not in (" ", "x"):
                continue
            it = parse_item(m[3], today)
            if it["kind"] != "exam" or it["date"] is None:
                continue
            title = it["title"].removeprefix("Plan prep:").strip()
            start = dt.datetime.combine(it["date"], dt.time(*it["time"]) if it["time"] else dt.time(23, 59, 59))
            out.append({"marker": it["marker"], "codes": course_codes(title), "words": exam_words(title),
                        "start": start, "allday": not it["time"], "date": it["date"]})
    return out


def exams_cache_path():
    return os.path.join(base_dir(), ".cache", "exams.json")


def exam_entry(it):
    """canvas.py の項目 dict（exam）→ 失効判定用の dict。"""
    due = it["due"]
    codes = course_codes(f"{it['label']} {it.get('course') or ''}")
    return {"marker": it.get("prep_marker") or it["marker"], "codes": codes, "words": exam_words(it["label"]),
            "start": due, "allday": bool(it.get("allday")), "date": due.date()}


def save_exams(items, keep_cal):
    """直近の同期で見えた試験（受験済み・過去も含む）を覚える。倉庫の Canvas 欄は終わった試験を落とすので、
    失効判定はここと倉庫の両方を見る。keep_cal＝カレンダーが取れなかった回は、前回のカレンダー由来を残す。"""
    import json
    p = exams_cache_path()
    cur = [exam_entry(i) for i in items if i.get("exam") and not i.get("drop")]
    if keep_cal:
        have = {e["marker"] for e in cur}
        cur += [e for e in load_exams_cache() if e["marker"].startswith("p:g") and e["marker"] not in have]
    out = [dict(e, codes=sorted(e["codes"]), words=sorted(e["words"]), start=e["start"].isoformat(),
                date=e["date"].isoformat()) for e in cur]
    write_if_changed(p, json.dumps(out, ensure_ascii=False, indent=1) + "\n")


def load_exams_cache():
    import json
    try:
        with open(exams_cache_path(), encoding="utf-8") as fh:
            rows = json.load(fh)
        return [dict(r, codes=set(r["codes"]), words=set(r["words"]), start=dt.datetime.fromisoformat(r["start"]),
                     date=dt.date.fromisoformat(r["date"])) for r in rows]
    except (OSError, ValueError, KeyError, TypeError):
        return []


def known_exams(blocks, today):
    """倉庫の試験 ＋ 直近の同期で見えた試験（過去・受験済みを含む）。"""
    return exams_from_blocks(blocks, today) + load_exams_cache()


def exam_passed(e, now):
    return now.date() > e["date"] if e["allday"] else now > e["start"]


def line_expired(body, exams, now):
    """この行（本文）が、すでに終わった試験の準備か。試験語が無ければ（マーカーが p:ID の一致でなければ）False。"""
    mm = MARKER.search(body)
    if mm and mm[1] == "p":
        hit = [e for e in exams if e["marker"] == f"p:{mm[2]}"]
        if hit:
            return all(exam_passed(e, now) for e in hit)
    title = norm_text(body)
    pm = last_paren(title)
    head = title[:pm.start()] if pm else title
    head = head.removeprefix("Plan prep:").strip()
    ok, _ = is_exam_title(head)  # 試験語あり・Quiz／final project 等は除外
    if not ok:
        return False
    codes = course_codes(head)
    cands = [e for e in exams if e["codes"] & codes]
    if not cands:
        return False
    words = exam_words(head)
    narrowed = [e for e in cands if e["words"] & words]
    cands = narrowed or cands
    return all(exam_passed(e, now) for e in cands)


def expire_exams(text, exams, now):
    """`# Today` の未完トップレベル行のうち、終わった試験の準備を `[-] … (expired)` にする（子の未完も）。

    ・[x]／[>]／他の節（Overdue・If time allows・Done today）・倉庫は触らない。繰り越しは [ ] だけを運ぶので、
      `[-]` は次の日に持ち越されず、作業量の合計にも入らない。冪等。(新しいテキスト, 変更の有無) を返す。
    """
    if not exams:
        return text, False
    lines = text.split("\n")
    parent_of = child_map(lines)
    kids = {}
    for c, par in parent_of.items():
        kids.setdefault(par, []).append(c)
    cur = "Today"
    changed = False
    for i, ln in enumerate(lines):
        cur = section_of(ln, cur)
        m = TASK_OPEN.match(ln)
        if cur != "Today" or not m or m[1] or i in parent_of:
            continue
        if not line_expired(m[2], exams, now):
            continue
        lines[i] = f"- [-] {m[2]} {EXPIRED}"
        changed = True
        for c in kids.get(i, []):
            cm = TASK_OPEN.match(lines[c])
            if cm:
                lines[c] = f"{cm[1]}- [-] {cm[2]} {EXPIRED}"
    return "\n".join(lines), changed


OVER_LINE = re.compile(r"^> ⚠ over by .* today$")


def refresh_over_line(text):
    """`> ⚠ over by …` を、いまの未完行（Today・Overdue）の合計から言い直す。収まれば消す。"""
    import math
    from .planner import CAPACITY, RATIO, line_size
    lines = text.split("\n")
    load = 0.0
    cur = "Today"
    for ln in lines:
        cur = section_of(ln, cur)
        m = TASK_OPEN.match(ln)
        if m and not m[1] and cur in ("Today", "Overdue"):
            load += line_size(m[2]) * RATIO
    for i, ln in enumerate(lines):
        if OVER_LINE.match(ln):
            if load > CAPACITY:
                lines[i] = f"> ⚠ over by {fmt_hm(math.ceil(load - CAPACITY))} today"
            else:
                del lines[i]
            break
    return "\n".join(lines)


def item_key(it):
    return it["prep_marker"] if it.get("exam") and it.get("prep_marker") else it["marker"]


def _norm_label(s):
    return re.sub(r"\s+", " ", s).strip().casefold()


def refresh_meta(text, items):
    """今日の `# Today` 欄の未完行に、Canvas／カレンダーの最新の締切時刻と ID を反映する。行の増減はしない。

    ★ 日次ファイルは 06:00 の roll で一度書いたきりで、その後の Canvas 側の変更（締切の変更・
      小テストの作り直しで ID が変わる）が届かなかった（2026-10-06: Module 3 Discussion の締切 21:20 が、
      実際は 09:20 に更新されていた。時刻の変換ミスではなく古い値のまま。Module 3 Quiz は ID が
      42988752 → 43037754 に変わった）。毎時の sync で `(due …)`／`(exam …)` の日付時刻と ⟨ID⟩ だけ直す。
    ・[x] 完了行・子・`## Overdue`／`## If time allows` の行は触らない。
    ・ID が Canvas から消えていたら、科目＋題名（正規化）が一致し、かつ今日のファイルに無い ID の項目が
      ちょうど1件のときだけ、その ID に付け替える。
    """
    by_key = {item_key(i): i for i in items}
    lines = text.split("\n")
    present = {f"{a}:{b}" for ln in lines for a, b in MARKER.findall(ln)}
    cur = "Today"
    changed = False
    for idx, ln in enumerate(lines):
        cur = section_of(ln, cur)
        m = TASK_OPEN.match(ln)
        if cur != "Today" or not m or m[1]:
            continue
        body = m[2]
        mm = MARKER.search(body)
        if not mm or mm[1] not in "aqdpg":
            continue
        key = f"{mm[1]}:{mm[2]}"
        is_prep = PREP_PREFIX in body
        it = by_key.get(key)
        if it is None and mm[1] in "aqdp":
            pm = last_paren(body)
            title = body[:pm.start()] if pm else body
            title = _norm_label(norm_text(title).removeprefix(PREP_PREFIX))
            hits = [i for i in items if bool(i.get("exam")) == is_prep and item_key(i) not in present
                    and _norm_label(i["label"]) == title]
            if len(hits) == 1:
                it = hits[0]
                nk = item_key(it)
                body = body.replace(f"⟨{key}⟩", f"⟨{nk}⟩")
                present.discard(key)
                present.add(nk)
        if it is None or it.get("done"):
            continue
        pm = last_paren(body)
        want = "exam" if it.get("exam") else "due"
        if pm and pm[1] == want:
            t = it["due"]
            when = wd_md(t.date()) + ("" if it.get("allday") else f" {t:%H:%M}")
            first = pm[2].split(" · ")[0]
            if first != when:
                new_inner = f"{want} {when}{pm[2][len(first):]}"
                body = body[:pm.start()] + f"({new_inner})" + body[pm.end():]
        if body != m[2]:
            lines[idx] = f"{m[1]}- [ ] {body}"
            changed = True
    return "\n".join(lines) if changed else text


def refresh_today(today, done_ids, now=None, done_today=None, items=None):
    p = day_path(today)
    if not os.path.exists(p):
        return
    text = read_raw(p)
    harvest(text, now or dt.datetime.now())
    if done_ids:
        text, _ = mark_canvas_done(text, done_ids)
    text = prep_fix_text(text)
    if items:
        text = refresh_meta(text, items)
    text, expired = expire_exams(text, known_exams(split_blocks(load_backlog()), today), now or dt.datetime.now())
    if expired:
        text = refresh_over_line(text)
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
