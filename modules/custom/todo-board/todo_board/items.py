"""items — タスク行の解析・描画、行末マーカー、作業量（size）、日付（M/D の年推定など）。

★ 行末マーカー `⟨a:12345⟩`（a=assignment q=quiz d=discussion h=倉庫の Dated 行のハッシュ、m=メール）:
  `<!-- -->` は leaf --inline で行内だとそのまま文字として出る（単独行だけ隠れる）ため、
  最も短く読みやすい形を選んだ。ID で突き合わせるので本文を人が編集しても壊れにくい。
"""
import datetime as dt
import hashlib
import re


TASK_OPEN = re.compile(r"^(\s*)- \[ \] (.*)$")
TASK_ANY = re.compile(r"^(\s*)- \[(.)\] (.*)$")
STAMP = re.compile(r"\s*[▶■][^(→⟨]*?(?:\(\d+m\))?(?=\s*\(since|\s*→|\s*⟨|$)")
ORIGIN = re.compile(r"\s*\(since (\d+)/(\d+)\)")
MARKER = re.compile(r"\s*⟨([a-z]):([0-9A-Za-z]+)⟩")
STARTED = re.compile(r"▶(\d+):(\d+)")
# 自分が書く括弧だけに一致させる（Canvas の題名に "(due 10/3 as an uploaded ...)" のような括弧があるため）
PAREN = re.compile(r"\((was due|late OK until|due|on|exam) ((?:[A-Za-z]{3} )?\d+/\d+(?: \d+:\d+)?(?: · [^)]*)?)\)")
LATE = re.compile(r"\(late until (\d+)/(\d+)(?: (\d+):(\d+))?\)")
DONE_MARK = re.compile(r"\(done (\d+)/(\d+)\)")  # 繰り越された完了済みの子／親（今日の集計に入れない）
HEAD_TODAY = re.compile(r"^(# Today \d+/\d+)(?:[ \t]+✓ .*?)?(\r?)$")
DUR_DONE = re.compile(r"■\d+:\d+ \((\d+)m\)")
EXAM_PREP_MIN = 30
CHECK_PREFIX = "Check if still submittable:"
WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def md(d):
    return f"{d.month}/{d.day}"  # ゼロ埋めなし


def wd_md(d):
    return f"{WD[d.weekday()]} {md(d)}"


def infer_date(m, d, today):
    """M/D の次の発生日。today-30日より前なら翌年（締切は未来、少し過ぎた分は遅れとして今年に残す）。"""
    try:
        c = dt.date(today.year, m, d)
        if c < today - dt.timedelta(days=30):
            c = dt.date(today.year + 1, m, d)
        return c
    except ValueError:
        return None


def infer_past(m, d, today):
    """(since M/D) 用: today 以前で最も新しい M/D。"""
    try:
        c = dt.date(today.year, m, d)
        if c > today:
            c = dt.date(today.year - 1, m, d)
        return c
    except ValueError:
        return None


def parse_size(s):
    """'30m' '2h' '1h30m' '1.5h' → 分。不正は None。"""
    s = s.strip().lower()
    m = re.fullmatch(r"(\d+(?:\.\d+)?)h", s)
    if m:
        return int(round(float(m[1]) * 60))
    m = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?", s)
    if m and (m[1] or m[2]):
        return int(m[1] or 0) * 60 + int(m[2] or 0)
    return None


def fmt_size(mins):
    if mins < 60:
        return f"{mins}m"
    if mins % 60 == 0:
        return f"{mins // 60}h"
    return f"{mins // 60}h{mins % 60}m"


def fmt_hm(mins):
    h, m = divmod(int(mins), 60)
    if h and m:
        return f"{h}h {m}m"
    return f"{h}h" if h else f"{m}m"


def norm_text(body):
    """突き合わせ用に、印・起票印・マーカー・チェック印を落とした本文。"""
    b = STAMP.sub("", body)
    b = ORIGIN.sub("", b)
    b = MARKER.sub("", b)
    b = b.replace("✓canvas", "").replace("✓mail", "")
    return re.sub(r"\s+", " ", b).strip()


def text_hash(body):
    return hashlib.sha1(norm_text(body).encode("utf-8")).hexdigest()[:6]


def last_paren(body):
    ms = list(PAREN.finditer(body))
    return ms[-1] if ms else None


def parse_item(body, today):
    """倉庫行の本文 → dict。due/on/exam の括弧が無ければ kind=None。"""
    marker = None
    mm = MARKER.search(body)
    if mm:
        marker = f"{mm[1]}:{mm[2]}"
    clean = norm_text(body)
    it = {"marker": marker, "kind": None, "title": clean, "date": None, "time": None,
          "size": None, "pts": None, "tail": "", "from": None}
    ms = list(PAREN.finditer(clean))
    if not ms:
        return it
    m = ms[-1]  # 題名側に似た括弧があっても、行末側（自分が付けた）を採る
    it["kind"] = m[1]
    it["title"] = clean[:m.start()].strip()
    it["tail"] = clean[m.end():].strip()
    parts = [p.strip() for p in m[2].split("·")]
    dm = re.match(r"(?:[A-Za-z]{3} )?(\d+)/(\d+)(?: (\d+):(\d+))?$", parts[0])
    if dm:
        it["date"] = infer_date(int(dm[1]), int(dm[2]), today)
        if dm[3]:
            it["time"] = (int(dm[3]), int(dm[4]))
    for p in parts[1:]:
        pm = re.fullmatch(r"(\d+(?:\.\d+)?)pt", p)
        fm = re.fullmatch(r"from (\d+)/(\d+)", p)
        if pm:
            it["pts"] = pm[1]
        elif fm:
            it["from"] = infer_past(int(fm[1]), int(fm[2]), today)
        else:
            s = parse_size(p)
            if s:
                it["size"] = s
    return it


def render_daily(it, marker):
    """候補 → 日次ファイルの行。exam は Plan prep: 付き、pt は出さない。"""
    when = wd_md(it["date"]) + (f" {it['time'][0]:02d}:{it['time'][1]:02d}" if it["time"] else "")
    inner = f"{it['kind']} {when}"
    if it["size"]:
        inner += f" · {fmt_size(it['size'])}"
    title = it["title"]
    if it["kind"] == "exam":
        title = f"Plan prep: {title}"
    s = f"- [ ] {title} ({inner})"
    if it["tail"]:
        s += f" {it['tail']}"
    return f"{s} {marker}" if marker else s


def parse_md_time(s):
    """'M/D' or 'M/D HH:MM' → (m, d, (h, mi) or None)。不正は ValueError。"""
    m = re.fullmatch(r"\s*(\d{1,2})/(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?\s*", s or "")
    if not m:
        raise ValueError(f"bad date '{s}' (use M/D or 'M/D HH:MM')")
    mo, da = int(m[1]), int(m[2])
    if not (1 <= mo <= 12 and 1 <= da <= 31):
        raise ValueError(f"bad date '{s}'")
    t = (int(m[3]), int(m[4])) if m[3] else None
    if t and not (0 <= t[0] < 24 and 0 <= t[1] < 60):
        raise ValueError(f"bad time in '{s}'")
    return mo, da, t
