"""planner — 着手期限（start_by）と Today／Overdue／If time allows の選択（roll の計画部分）。

★ 設計（vault の todo-board-design「設計の改訂」）:
  - 06:00 に1回だけ、倉庫から「着手期限が今日までに来たもの」を全部 Today に出す（件数上限なし）。
    着手期限 = 締切日 − ceil(作業量×1.5 / 120分) 日。合計が1日の想定を超えたら警告行を出す（隠さない）。
  - 余ったら `## If time allows` に先の着手期限が近い順に空き分だけ。翌朝に再導出するので繰り越さない。
"""
import datetime as dt
import math

from .store import load_state
from .items import (
    CHECK_PREFIX,
    EXAM_PREP_MIN,
    fmt_hm,
    fmt_size,
    infer_date,
    LATE,
    MARKER,
    norm_text,
    PAREN,
    parse_item,
    parse_size,
    render_daily,
    TASK_ANY,
    TASK_OPEN,
    text_hash,
    wd_md,
)
from .backlog import get_block


RATIO = 1.5  # 実績で更新する想定の倍率（初期値）
CAPACITY = 120  # 1日の作業可能分（record-blocks は膨らむので控えめ）
DEFAULT_SIZE = 60
EXAM_LEAD_DAYS = 7
IF_TIME = "If time allows"
OVERDUE = "Overdue"
CHECK_MIN = 10


def plan_size(it):
    if it["kind"] == "exam":
        return EXAM_PREP_MIN
    return it["size"] or DEFAULT_SIZE


def start_by(it):
    if it["date"] is None:
        return None
    if it["kind"] == "exam":
        return it["date"] - dt.timedelta(days=EXAM_LEAD_DAYS)
    if it["kind"] == "on":
        return it["date"]
    if it.get("from"):
        return it["from"]  # メール: digest の日から出す（締切が先でも、要対応は早めに見せる）
    days = math.ceil(plan_size(it) * RATIO / CAPACITY)
    sb = it["date"] - dt.timedelta(days=days)
    if it["time"] and it["time"][0] < 12:
        sb -= dt.timedelta(days=1)  # 午前の締切は当日を使えない
    return sb


def due_key(it):
    t = it["time"] or (23, 59)
    return (it["date"], t)


def aqd(marker):
    return bool(marker) and marker[0] in "aqd" and marker[1:2] == ":"


def candidates(blocks, today):
    out = []
    st = load_state()
    skip = set(st["done_ids"]) | set(st["checked_ids"])
    for name in ("Canvas", "Mail", "Dated"):
        b = get_block(blocks, name)
        if not b:
            continue
        for ln in b[1]:
            m = TASK_OPEN.match(ln)
            if not m:
                continue
            it = parse_item(m[2], today)
            if it["kind"] is None or it["date"] is None:
                continue
            if it["marker"] in skip:
                continue  # 手で [x] にした／確認済みの印（Canvas が追いつくまで再計画しない）
            if it["kind"] == "exam" and it["date"] < today:
                continue  # 終わった試験の準備は出さない
            if it["marker"] is None:
                it["marker"] = f"h:{text_hash(m[2])}"
            it["overdue"] = bool(name == "Canvas" and it["kind"] == "due" and aqd(it["marker"])
                                 and it["date"] < today)
            it["late"] = None
            lm = LATE.search(it["tail"])
            if lm:
                it["tail"] = LATE.sub("", it["tail"]).strip()
                ld = infer_date(int(lm[1]), int(lm[2]), today)
                if ld:
                    it["late"] = (ld, (int(lm[3]), int(lm[4])) if lm[3] else None)
            it["start"] = start_by(it)
            if it["overdue"]:
                if it["late"]:
                    if it["late"][0] < today:
                        continue  # 提出期限（lock）が過ぎた
                    ld, lt = it["late"]
                    when = wd_md(ld) + (f" {lt[0]:02d}:{lt[1]:02d}" if lt else "")
                    it["osize"] = it["size"] or DEFAULT_SIZE
                    it["line"] = (f"- [ ] {it['title']} (late OK until {when} · {fmt_size(it['osize'])})"
                                  f" ⟨{it['marker']}⟩")
                else:
                    it["osize"] = CHECK_MIN
                    it["line"] = (f"- [ ] {CHECK_PREFIX} {it['title']} (was due {wd_md(it['date'])}"
                                  f" · {fmt_size(CHECK_MIN)}) ⟨{it['marker']}⟩")
            else:
                it["line"] = render_daily(it, f"⟨{it['marker']}⟩")
            out.append(it)
    return out


def line_size(body):
    """日次行の `· Nh` から分。無ければ既定。exam の Plan prep は 30m。"""
    ms = list(PAREN.finditer(body))
    if ms:
        m = ms[-1]
        for p in m[2].split("·")[1:]:
            s = parse_size(p)
            if s:
                return s
    return DEFAULT_SIZE


def plan_today(today, blocks, carried):
    """(警告行 or None, Must 行[], Overdue 行[], If-time 行[])。carried は繰り越し済みの日次行。"""
    present_markers = set()
    present_text = set()
    load = 0.0
    for ln in carried:
        m = TASK_ANY.match(ln)
        if not m or m[1]:
            continue  # 子は親の作業量に含まれる（二重に数えない・計画照合にも使わない）
        mm = MARKER.search(m[3])
        if mm:
            present_markers.add(f"{mm[1]}:{mm[2]}")
        present_text.add(norm_text(m[3]))
        if m[2] == " ":
            load += line_size(m[3]) * RATIO  # 完了済みの親（子だけ未完）は負荷に入れない
    cands = []
    for it in candidates(blocks, today):
        if it["marker"] in present_markers:
            continue
        if not it["overdue"] and norm_text(it["line"][6:]) in present_text:
            continue
        cands.append(it)
    over = sorted([c for c in cands if c["overdue"]], key=due_key)
    cands = [c for c in cands if not c["overdue"]]
    must = sorted([c for c in cands if c["start"] <= today], key=due_key)
    rest = sorted([c for c in cands if c["start"] > today], key=lambda c: (c["start"], due_key(c)))
    load += sum(plan_size(c) * RATIO for c in must)
    load += sum(c["osize"] * RATIO for c in over)
    warn = None
    later = []
    if load > CAPACITY:
        warn = f"> ⚠ over by {fmt_hm(math.ceil(load - CAPACITY))} today"
    else:
        spare = CAPACITY - load
        for c in rest:
            if later and spare <= 0:
                break
            later.append(c)
            spare -= plan_size(c) * RATIO
    return warn, [c["line"] for c in must], [c["line"] for c in over], [c["line"] for c in later]
