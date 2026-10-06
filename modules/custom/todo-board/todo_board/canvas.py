"""canvas — Canvas 連携: トークン（Keychain／rbw）、API 取得、planner／submissions/self、lock_at キャッシュ、倉庫 `# Canvas` 欄。

トークンは print/log しない。fixture モード（env TODO_BOARD_CANVAS_FIXTURE）ではネットワークもトークンも使わない。
`http_get_json` は本モジュール内の関数から名前で呼ばれる（テストは `canvas.http_get_json` を差し替える）。
"""
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request

from .store import (
    backlog_path,
    day_path,
    is_excluded_text,
    load_aliases,
    load_excluded,
    load_state,
    lock_cache_path,
    prune_state,
    read_raw,
    save_state,
    save_status,
    save_status_key,
    write_if_changed,
)
from .items import EXAM_PREP_MIN, fmt_size, last_paren, MARKER, md, TASK_ANY
from .backlog import CANVAS_NOTE, get_block, join_blocks, load_backlog, split_blocks
from .daily import open_markers, refresh_today, save_exams
from .gcal import calendar_exams


LOCK_TTL_H = 24
CANVAS_BASE = "https://canvas.txstate.edu/api/v1"


class CanvasError(Exception):
    pass


def _run_out(args, timeout):
    """子プロセスの stdout（空なら ""）。stdin は閉じて、どんな対話プロンプトも出させない。"""
    try:
        r = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _run_rc(args, timeout):
    try:
        return subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=timeout).returncode
    except Exception:
        return 1


def get_token():
    """Keychain → だめなら rbw（解錠済みのときだけ）。★ トークンは print/log しない。

    launchd には pinentry が無いので、rbw がロック中なら問い合わせず諦める（`unlocked` で先に確認）。
    """
    sec = os.environ.get("TODO_BOARD_SECURITY") or "/usr/bin/security"
    tok = _run_out([sec, "find-generic-password", "-s", "canvas-txst-token", "-w"], 10)
    if tok:
        return tok
    rb = os.environ.get("TODO_BOARD_RBW") or shutil.which("rbw")
    if rb and _run_rc([rb, "unlocked"], 10) == 0:
        tok = _run_out([rb, "get", "canvas-open-api"], 15)
        if tok:
            return tok
        raise CanvasError("no Canvas token (Keychain missing, rbw lookup failed)")
    raise CanvasError("no Canvas token (Keychain missing, rbw locked)")


def to_chicago(s):
    """UTC ISO → America/Chicago の naive datetime。zoneinfo が無い環境は米国の夏時間規則で手計算。"""
    u = dt.datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
    try:
        from zoneinfo import ZoneInfo
        return u.replace(tzinfo=dt.timezone.utc).astimezone(ZoneInfo("America/Chicago")).replace(tzinfo=None)
    except Exception:
        y = u.year
        d1 = dt.datetime(y, 3, 8 + (6 - dt.date(y, 3, 8).weekday()) % 7, 8)  # 第2日曜 2:00 CST = 8:00 UTC
        d2 = dt.datetime(y, 11, 1 + (6 - dt.date(y, 11, 1).weekday()) % 7, 7)  # 第1日曜 2:00 CDT = 7:00 UTC
        return u + dt.timedelta(hours=-5 if d1 <= u < d2 else -6)


SEASONS = {"FA", "SP", "SU", "WI", "FALL", "SPR", "SPRG", "SUM", "WINT"}


def course_label(name):
    name = name or ""
    for m in re.finditer(r"([A-Za-z]{2,4})[\s._-]?(\d{4})", name):
        if m[1].upper() not in SEASONS:  # "Fa2026" のような学期表記はコードではない
            return f"{m[1].upper()}{m[2]}"
    low = name.lower()
    for k, v in load_aliases().items():
        if k.lower() in low:
            return v
    return name.strip()[:12]


EXAM_RE = re.compile(r"\b(midterm|final|exam|test)s?\b", re.I)
PAPER_RE = re.compile(r"paper|essay|project|report|outline|draft|revision", re.I)


def is_exam(title, ptype):
    return (ptype != "discussion_topic" and not re.search(r"practice|take[- ]?home", title, re.I)
            and not PAPER_RE.search(title) and bool(EXAM_RE.search(title)))


def size_for(title, ptype):
    if re.search(r"practice", title, re.I):
        return 15
    # 種類はタイトルでも見る。Canvas は quiz/discussion を assignment 型で返すことがある
    # （実データ：CS3360 "Module 3 Quiz" / "Module 3 Discussion" が assignment で 2h になった）。
    if ptype == "discussion_topic" or re.search(r"discussion", title, re.I):
        return 30
    if PAPER_RE.search(title):
        return 360
    if ptype == "quiz" or re.search(r"\bquiz", title, re.I):
        return 30
    return 120  # zybook|exercise|lab|homework|hw|assignment と既定は同じ


def normalize_item(raw):
    """planner item → dict。対象外の型は None。"""
    ptype = raw.get("plannable_type")
    kind = {"assignment": "a", "quiz": "q", "discussion_topic": "d"}.get(ptype)
    pl = raw.get("plannable") or {}
    if not kind or not raw.get("plannable_date") or not raw.get("plannable_id"):
        return None
    title = re.sub(r"\s+", " ", str(pl.get("title") or "").replace("⟨", "").replace("⟩", "")).strip()
    sub = raw.get("submissions")
    done = False
    if isinstance(sub, dict):
        # 実データのキー: submitted/graded/excused/late/missing/needs_grading/has_feedback/redo_request。
        # 提出済み・採点待ち（needs_grading）・採点済み・免除はすべて「もう自分の手番ではない」
        done = bool(sub.get("submitted") or sub.get("graded") or sub.get("excused")
                    or sub.get("needs_grading"))
    ov = raw.get("planner_override") or {}
    if ov.get("marked_complete"):
        done = True
    submitted_at = None
    if isinstance(sub, dict) and sub.get("submitted_at"):
        try:
            submitted_at = to_chicago(sub["submitted_at"]).date()  # 実データの planner には無いことが多い
        except (ValueError, TypeError):
            pass
    course = course_label(raw.get("context_name"))
    if is_excluded_text(course, load_excluded()) or is_excluded_text(raw.get("context_name"), load_excluded()):
        return None
    exam = is_exam(title, ptype)
    if title.upper().startswith(course.upper()):
        label = title
    else:
        label = f"{course} {title}".strip()
    return {
        "marker": f"{kind}:{raw['plannable_id']}",
        # 試験の「準備」は試験本体と別の ID（p:）で持つ。準備を [x] にしても a:ID（試験そのもの）は閉じない
        "prep_marker": f"p:{raw['plannable_id']}",
        "course": course,
        "label": label,
        "due": to_chicago(raw["plannable_date"]),
        "pts": pl.get("points_possible"),
        "size": EXAM_PREP_MIN if exam else size_for(title, ptype),
        "exam": exam,
        "done": done,
        "kind": kind,
        "id": raw["plannable_id"],
        "course_id": raw.get("course_id") or pl.get("course_id"),
        "lock_raw": pl.get("lock_at"),
        "submitted_at": submitted_at,
    }


def http_get_json(path):
    """Canvas API の GET（path は /courses/... のように API ルートからの相対）。

    fixture モード（env TODO_BOARD_CANVAS_FIXTURE）ではネットワークもトークンも使わず、
    env TODO_BOARD_LOCK_FIXTURE の JSON（{path: オブジェクト}）から返す。無ければ CanvasError。
    """
    if os.environ.get("TODO_BOARD_CANVAS_FIXTURE"):
        fx = os.environ.get("TODO_BOARD_LOCK_FIXTURE")
        if fx:
            with open(fx, encoding="utf-8") as fh:
                data = json.load(fh)
            if path in data:
                return data[path]
        raise CanvasError("fixture: no such path")
    tok = get_token()
    req = urllib.request.Request(CANVAS_BASE + path, headers={"Authorization": f"Bearer {tok}",
                                                                "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise CanvasError(f"Canvas HTTP {e.code}")
    except Exception as e:
        raise CanvasError(f"Canvas fetch failed: {type(e).__name__}"[:80])


LOCK_ENDPOINT = {"a": "assignments", "q": "quizzes", "d": "discussion_topics"}


def parse_lock(s):
    try:
        return to_chicago(s) if s else None
    except (ValueError, TypeError):
        return None


def lock_lookup(it, now):
    """過去締切・未提出の項目の lock_at（Chicago の naive datetime、不明は None）。

    planner の plannable に lock_at があればそれを使う。無ければ個別 API を引き、結果を
    <base>/.cache/lock_at.json に24時間キャッシュする（None＝lock 無しも保存。失敗は保存しない）。
    """
    if it.get("lock_raw"):
        return parse_lock(it["lock_raw"])
    ep = LOCK_ENDPOINT.get(it["kind"])
    if not ep or not it.get("course_id"):
        return None
    key = it["marker"]
    try:
        with open(lock_cache_path(), encoding="utf-8") as fh:
            cache = json.load(fh)
    except (OSError, ValueError):
        cache = {}
    if not isinstance(cache, dict):
        cache = {}
    e = cache.get(key)
    if isinstance(e, dict):
        try:
            age = now - dt.datetime.strptime(e["fetched"], "%Y-%m-%dT%H:%M")
            if age < dt.timedelta(hours=LOCK_TTL_H):
                return parse_lock(e.get("lock_at"))
        except (KeyError, ValueError):
            pass
    try:
        obj = http_get_json(f"/courses/{it['course_id']}/{ep}/{it['id']}")
    except CanvasError:
        return None
    raw = obj.get("lock_at") if isinstance(obj, dict) else None
    cache[key] = {"lock_at": raw, "fetched": now.strftime("%Y-%m-%dT%H:%M")}
    write_if_changed(lock_cache_path(), json.dumps(cache, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    return parse_lock(raw)


def fetch_canvas(today, now=None):
    """正規化済み項目のリスト。env TODO_BOARD_CANVAS_FIXTURE があればネットワークを使わない（テスト用）。"""
    now = now or dt.datetime.combine(today, dt.time(6, 0))
    fx = os.environ.get("TODO_BOARD_CANVAS_FIXTURE")
    if fx:
        with open(fx, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and "__error__" in data:
            raise CanvasError(str(data["__error__"]))
        raw_items = data
    else:
        tok = get_token()
        q = urllib.parse.urlencode({"start_date": (today - dt.timedelta(days=7)).isoformat(),
                                    "end_date": (today + dt.timedelta(days=35)).isoformat(),
                                    "per_page": 100})
        url = f"{CANVAS_BASE}/planner/items?{q}"
        raw_items = []
        pages = 0
        try:
            while url and pages < 20:
                req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}",
                                                           "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=30) as r:
                    raw_items.extend(json.loads(r.read().decode("utf-8")))
                    link = r.headers.get("Link") or ""
                nxt = re.search(r'<([^>]+)>;\s*rel="next"', link)
                url = nxt[1] if nxt else None
                pages += 1
        except urllib.error.HTTPError as e:
            raise CanvasError(f"Canvas HTTP {e.code}")
        except Exception as e:  # トークンは URL/ヘッダにしか無く、例外文字列には入らないが念のため除去
            raise CanvasError(f"Canvas fetch failed: {type(e).__name__}"[:80])
    items = []
    for raw in raw_items:
        it = normalize_item(raw)
        if it:
            items.append(it)
    for it in items:
        it["drop"] = False
        it["late_until"] = None
        # planner の submissions は外部ツール連携（zyBooks 等の LTI）の提出を拾わない。
        # 実データ：zyBook Ex3 は planner で submitted=False だが、submissions/self は
        # workflow_state=pending_review（2026-10-02、本人「出したような気がする」で発覚）。
        # 未完了に見える assignment だけ個別に確かめる（数十件・毎時なので許容）。
        if not it["done"] and not it["exam"] and it["marker"].startswith("a:") and it.get("course_id"):
            try:
                sub = http_get_json(f"/courses/{it['course_id']}/assignments/{it['id']}/submissions/self")
                if (sub.get("workflow_state") in ("submitted", "pending_review", "graded")
                        or sub.get("submitted_at") or sub.get("score") is not None):
                    it["done"] = True
                    try:
                        if sub.get("submitted_at"):
                            it["submitted_at"] = to_chicago(sub["submitted_at"]).date()
                    except (ValueError, TypeError):
                        pass
            except CanvasError:
                pass  # 確かめられなければ planner の判定のまま
        if it["due"] < now and not it["done"] and not it["exam"]:
            lock = lock_lookup(it, now)
            if lock and lock <= now:
                it["drop"] = True  # もう提出できない
            elif lock:
                it["late_until"] = lock
    return items


def canvas_line(it):
    t = it["due"]
    if it["exam"]:
        # 試験は準備タスク（Plan prep）として出す。提出は来ないので Canvas 側の完了では閉じない。
        # ID は準備専用の p:（試験本体の a:ID と別。カレンダー由来の試験は g: の本体を持たず p:g… だけ）
        when = md(t) + ("" if it.get("allday") else f" {t:%H:%M}")
        return f"- [ ] {it['label']} (exam {when} · {fmt_size(it['size'])}) ⟨{it.get('prep_marker') or it['marker']}⟩"
    parts = [f"due {md(t)} {t:%H:%M}"]
    try:
        pts = float(it["pts"] or 0)
    except (TypeError, ValueError):
        pts = 0
    if pts > 0:
        parts.append(f"{int(pts) if pts == int(pts) else pts}pt")
    parts.append(fmt_size(it["size"]))
    tag = ""
    lu = it.get("late_until")
    if lu:
        tag = f" (late until {md(lu)} {lu:%H:%M})"
    return f"- [ ] {it['label']} ({' · '.join(parts)}){tag} ⟨{it['marker']}⟩"


def rewrite_canvas_section(text, items, today, keep_cal=False):
    """`# Canvas` ブロックだけを差し替える。他のブロックはバイト列のまま。

    keep_cal: カレンダーが取れなかった回は、前回の `g:`／`p:g…` 由来の試験行を（[x] も含め）そのまま残す。
    """
    blocks = split_blocks(text)
    old = get_block(blocks, "Canvas")
    old_done = set()
    kept = []
    if old:
        for ln in old[1]:
            m = TASK_ANY.match(ln)
            mm = MARKER.search(m[3]) if m else None
            if keep_cal and mm and (mm[1] == "g" or mm[2].startswith("g") and mm[1] == "p"):
                kept.append(ln)
            if m and m[2] == "x" and mm and last_paren(m[3]) and last_paren(m[3])[1] == "exam":
                old_done.add(f"{mm[1]}:{mm[2]}")  # 試験の準備は人が閉じた状態を保つ
                if mm[1] == "a":
                    old_done.add(f"p:{mm[2]}")  # 旧形式（準備が本体と同じ a:ID）の閉じた状態を p: に引き継ぐ
    open_items = []
    for it in items:
        if it["done"] and not it["exam"]:
            continue
        if it["done"] and it["exam"]:
            continue  # 受験済みの試験は準備不要
        if it["due"].date() < today - dt.timedelta(days=7):
            continue
        if it.get("drop"):
            continue  # lock_at が過ぎて提出不能
        open_items.append(it)
    open_items.sort(key=lambda i: (i["due"], i["label"]))
    lines = ["# Canvas", CANVAS_NOTE]
    for it in open_items:
        ln = canvas_line(it)
        if (it.get("prep_marker") if it["exam"] else it["marker"]) in old_done:
            ln = ln.replace("- [ ]", "- [x]", 1)
        lines.append(ln)
    lines.extend(kept)
    lines.append("")
    if old:
        old[1] = lines
    else:
        pos = 0
        if blocks and blocks[0][0] is None:
            pos = 1
        blocks.insert(pos, ["Canvas", lines])
    return join_blocks(blocks)


def canvas_done_today(items, today, prev_open):
    """今日提出された Canvas 項目（正規化済み）→ [(marker, label, "canvas")]。

    提出日は submissions/self の submitted_at（Chicago）があればそれ。planner 経由の提出済みには日付が無いので、
    「sync が初めて完了と見た日」を .state.json の done_seen に記録して使う。ただし初見が最初から完了だった項目
    （導入前・1週間前の提出など）は日付不明＝"old" として出さない（直前の倉庫か今日のファイルで未完に見えていた
    ＝未完→完了の遷移を見た項目だけが今日扱い）。
    """
    st = load_state()
    seen = st["done_seen"]
    changed = False
    out = []
    for it in items:
        if not it["done"] or it["exam"]:
            continue
        mk = it["marker"]
        sd = it.get("submitted_at")
        if sd is None:
            if mk not in seen:
                seen[mk] = today.isoformat() if mk in prev_open else "old"
                changed = True
            try:
                sd = dt.date.fromisoformat(seen[mk])
            except ValueError:
                sd = None
        if sd == today:
            out.append((mk, it["label"], "canvas"))
    if changed:
        save_state(st)
    return out


def canvas_refresh(today, now):
    """取得して倉庫の Canvas 欄・状態・今日のファイルを更新。(ok, 提出済み ID 集合) を返す。"""
    try:
        items = fetch_canvas(today, now)
    except CanvasError as e:
        save_status(False, str(e), now)
        refresh_today(today, None, now)
        return False, set()
    except Exception as e:
        save_status(False, f"Canvas fetch failed: {type(e).__name__}", now)
        refresh_today(today, None, now)
        return False, set()
    old_bl = load_backlog()
    prev_open = open_markers(old_bl)
    if os.path.exists(day_path(today)):
        prev_open |= open_markers(read_raw(day_path(today)))
    # カレンダーの 📕（Canvas に載らない試験）。取れなくても Canvas 側は止めない（前回の試験行を残す）
    try:
        cal, cal_st = calendar_exams(today, items, now)
    except Exception as e:
        cal, cal_st = None, {"state": "error", "error": f"calendar failed: {type(e).__name__}"}
    save_status_key("calendar", cal_st)
    all_items = items + (cal or [])
    save_exams(all_items, keep_cal=cal is None)
    text = rewrite_canvas_section(old_bl, all_items, today, keep_cal=cal is None)
    write_if_changed(backlog_path(), text)
    save_status(True, None, now)
    done_ids = {i["marker"] for i in items if i["done"] and not i["exam"]}
    done_today = canvas_done_today(items, today, prev_open)
    refresh_today(today, done_ids, now, done_today, all_items)  # 先に今日の [x] を記憶し、そのあと Canvas に無い項目を忘れる
    prune_state("aqd", {i["marker"] for i in items})
    return True, done_ids
