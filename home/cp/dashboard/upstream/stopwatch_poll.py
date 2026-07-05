#!/usr/bin/env python3
"""SOLVE STOPWATCH (#36) poller — start/freeze detection for the CP dashboard.

Definition (identical to the measured solve-time dataset,
x1nano analyze_solve_times.py / vault atcoder-solve-time-data):
  start  = birth time of ~/cp/contests/<c>/<p>/.problem_url
           (cp-go writes it once; `>` truncates in place so btime never moves)
  freeze = epoch of the FIRST AC submission at/after start (WA keeps running)
  expire = 4h after start (beyond the single-session cap → back to READY)

AC sources, in order: local submissions cache → AtCoder official submissions
page (fast, needs REVEL_SESSION in Keychain via cp-login; the page went
login-only in the 2025 anti-bot wave) → kenkoooo API (no auth, crawler lag).

Reactivity (REACTIVITY SPEC の二段階点灯):
  - `oj test` success drops a marker (oj wrapper in cp/tools.nix) and kicks one
    pass → the board shows a ✓ hint and the poller ARMS: it watches at 10s
    intervals for ~45s per invocation (authenticated path only), because a
    passing local test predicts an imminent browser submission.
  - A pending submission (WJ / n:m row) = JUDGING: provisional stop at the
    submission epoch. AC finalizes that value; WA resumes the clock.

Invocation: launchd every 60s (idle = no network, exits fast) + cp-go /
oj-wrapper kicks. State: ~/.cache/cp-dashboard/stopwatch.json (read by
gen-draft-data.py). Frozen sessions append to solve_times.jsonl (30s–4h
filter as in the n=288 snapshot; dedupe on task_id+start).
"""

import fcntl
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_stats import ATCODER_BASE, KENKOOOO_BASE, _fetch, _fetch_json  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent          # ~/cp-dashboard
CACHE = Path(os.environ.get("CP_DASH_CACHE", Path.home() / ".cache" / "cp-dashboard"))
CP_CONTESTS = Path(os.environ.get("CP_DASH_CONTESTS", Path.home() / "cp" / "contests"))
STATE = CACHE / "stopwatch.json"
DATASET = CACHE / "solve_times.jsonl"
MARKER = CACHE / "test-passed.json"
CAP_S = 4 * 3600
MIN_S = 30
ARMED_WINDOW_S = 300      # oj test 通過後この間は臨戦態勢
TESTED_SHOW_S = 600       # ✓ tests ヒントの表示窓
FAST_INTERVAL_S = 10
FAST_BUDGET_S = 35        # ループ判定は sleep 前＝最終ポーリングは t0+45s 以内に収まる

ATCODER_KEYCHAIN_SERVICE = "atcoder-revel-session"
FIXTIME_RE = re.compile(r'<time class=["\']fixtime fixtime-second["\']>([^<]+)</time>')
LABEL_RE = re.compile(r'<span class=["\']label[^"\']*["\'][^>]*>([^<]+)</span>')
# 確定ステータス。これ以外（WJ・"3/15" 進捗等）は判定中とみなす
FINAL_RESULTS = {"AC", "WA", "TLE", "MLE", "RE", "OLE", "IE", "CE", "WR", "QLE"}


def load_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except Exception:
        return default


def load_json_str(s):
    try:
        return json.loads(s)
    except Exception:
        return None


def username():
    wl = load_json(ROOT / "watchlist.json", [])
    return wl[0] if wl else None


def latest_candidate():
    """Most recently opened problem, or None."""
    best = None
    if not CP_CONTESTS.is_dir():
        return None
    for f in CP_CONTESTS.glob("*/*/.problem_url"):
        try:
            start = f.stat().st_birthtime
        except (OSError, AttributeError):
            continue
        if best is None or start > best[1]:
            best = (f, start)
    if best is None:
        return None
    f, start = best
    url = (f.read_text().strip() if f.is_file() else "")
    if "/tasks/" not in url:
        return None
    return {"task_id": url.rsplit("/tasks/", 1)[1], "url": url,
            "contest": f.parent.parent.name, "start": start}


def grade_of(task_id):
    novi = load_json(CACHE / "novisteps.json", {}) or {}
    for wb in (novi.get("workbooks") or {}).values():
        for t in wb.get("tasks", []):
            if t.get("task_id") == task_id:
                return t.get("grade")
    return None


def atcoder_session():
    """REVEL_SESSION from env (tests) or the login Keychain. None if absent.
    Stored by cp-login with -T /usr/bin/security so launchd reads it silently."""
    env = os.environ.get("CP_ATCODER_SESSION")
    if env:
        return env
    try:
        r = subprocess.run(
            ["/usr/bin/security", "find-generic-password",
             "-s", ATCODER_KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    tok = r.stdout.strip()
    return tok if r.returncode == 0 and tok else None


def scan_atcoder_rows(user, contest, task_id, start, session, retries=1):
    """速報経路: 公式の提出一覧（要ログイン）を全ステータスで走査。
    Returns None（認証切れ/取得失敗/構造変化 → kenkoooo フォールバック）or
      {"first_ac": epoch|None,      # start 以降の初AC
       "judging_at": epoch|None,    # 判定中(WJ/n:m)の提出時刻（最新）
       "last_wa": epoch|None}       # start 以降の最新WA
    """
    url = (f"{ATCODER_BASE}/contests/{contest}/submissions"
           f"?f.Task={task_id}&f.User={user}")
    raw = _fetch(url, retries=retries,
                 headers={"Cookie": f"REVEL_SESSION={session}"})
    if raw is None:
        return None
    html = raw.decode("utf-8", "replace")
    if "<title>Sign In" in html:
        print("[stopwatch] atcoder cookie expired — run cp-login", file=sys.stderr)
        return None
    acs, was, judging = [], [], []
    suspect = False   # 対象行はあるのに時刻/ラベルが取れない＝構造変化の兆候
    for row in html.split("<tr>"):
        # クエリフィルタを信用せず行単位で task/user を検証してから読む
        if f"/contests/{contest}/tasks/{task_id}" not in row:
            continue
        if f"/users/{user}" not in row:
            continue
        tm = FIXTIME_RE.search(row)
        lm = LABEL_RE.search(row)
        if not tm or not lm:
            suspect = True
            continue
        try:
            epoch = int(datetime.strptime(
                tm.group(1).strip(), "%Y-%m-%d %H:%M:%S%z").timestamp())
        except ValueError:
            suspect = True
            continue
        if epoch < int(start):
            continue
        result = lm.group(1).strip()
        if result == "AC":
            acs.append(epoch)
        elif result == "WA":
            was.append(epoch)
        elif result not in FINAL_RESULTS:
            judging.append(epoch)
    if suspect and not acs:
        # 「無い」と断定せず kenkoooo に回す（構造変化で両経路が死ぬのを防ぐ）
        print("[stopwatch] atcoder page structure changed? — fallback",
              file=sys.stderr)
        return None
    return {"first_ac": min(acs) if acs else None,
            "judging_at": max(judging) if judging else None,
            "last_wa": max(was) if was else None}


def ac_from_cache(user, task_id, start):
    subs = load_json(CACHE / f"submissions_{user}.json", []) or []
    acs = [s["epoch_second"] for s in subs
           if s.get("problem_id") == task_id and s.get("result") == "AC"
           and s.get("epoch_second", 0) >= int(start)]
    return min(acs) if acs else None


def ac_from_kenkoooo(user, task_id, start):
    url = (f"{KENKOOOO_BASE}/atcoder-api/v3/user/submissions"
           f"?user={user}&from_second={int(start)}")
    batch = _fetch_json(url)
    if not isinstance(batch, list):
        return None
    acs = [s["epoch_second"] for s in batch
           if s.get("problem_id") == task_id and s.get("result") == "AC"]
    return min(acs) if acs else None


def append_dataset(rec):
    """Append a frozen session once (dedupe on task_id+start).

    flock: the launchd 60s timer and the cp-go / oj-wrapper kicks can run
    concurrently; without the lock both pass the dedupe read and double-append."""
    key = (rec["task_id"], int(rec["start"]))
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / "stopwatch.lock").open("w") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if DATASET.is_file():
            for line in DATASET.read_text().splitlines():
                old = load_json_str(line)
                if old and (old.get("task_id"), int(old.get("start", 0))) == key:
                    return False
        with DATASET.open("a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return True


def write_state(new):
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(new, ensure_ascii=False) + "\n")
    os.replace(tmp, STATE)


def refresh_board():
    """Regenerate draft-data.js; touch inject.js so the live layer reloads
    even before it learns to watch draft-data.js itself."""
    gen = ROOT / "web" / "gen-draft-data.py"
    if gen.is_file():
        r = subprocess.run([sys.executable, str(gen)], check=False,
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"[stopwatch] gen-draft-data failed: {r.stderr.strip()}",
                  file=sys.stderr)
    inject = ROOT / "web" / "inject.js"
    if inject.is_file():
        os.utime(inject, None)


def tested_at_for(task_id, now):
    """oj test 成功マーカー（表示窓内・同一 task のみ）。"""
    m = load_json(MARKER, {}) or {}
    if m.get("task_id") == task_id and now - m.get("passed_at", 0) < TESTED_SHOW_S:
        return int(m["passed_at"])
    return None


def build_state(cand, user, session, prev, now, fast=False):
    """4h 窓内の候補について、1回の観測で現在状態を作る。
    fast=True は臨戦ループ内＝リトライ無しで1回だけ聞く（時間予算を守る）。"""
    base = {
        "task_id": cand["task_id"],
        "contest": cand["contest"],
        "start": int(cand["start"]),
        "grade": grade_of(cand["task_id"]),
        "updated_at": int(now),
    }
    # Frozen result is final for this start; don't re-poll once recorded.
    if (prev.get("status") == "frozen"
            and prev.get("task_id") == cand["task_id"]
            and prev.get("start") == int(cand["start"])):
        return {**prev, "updated_at": int(now)}

    ac = ac_from_cache(user, cand["task_id"], cand["start"])
    probe = None
    if ac is None and session:
        probe = scan_atcoder_rows(user, cand["contest"], cand["task_id"],
                                  cand["start"], session,
                                  retries=0 if fast else 1)
        if probe is not None:
            ac = probe["first_ac"]
    if ac is None and probe is None:
        # cookie 不在 or 公式経路が死んでいる時だけ kenkoooo に聞く
        ac = ac_from_kenkoooo(user, cand["task_id"], cand["start"])

    if ac is not None:
        elapsed = int(ac - cand["start"])
        new = {**base, "status": "frozen", "ac_epoch": int(ac),
               "elapsed": elapsed}
        if MIN_S <= elapsed <= CAP_S:
            if append_dataset({"task_id": cand["task_id"],
                               "contest": cand["contest"],
                               "start": int(cand["start"]),
                               "ac_epoch": int(ac),
                               "elapsed": elapsed,
                               "grade": base["grade"]}):
                print(f"[stopwatch] dataset += {cand['task_id']} {elapsed}s")
        return new

    new = {**base, "status": "running"}
    tested = tested_at_for(cand["task_id"], now)
    if tested:
        new["tested_at"] = tested
    if probe:
        if probe["judging_at"]:
            new["judging"] = True
            new["submitted_at"] = probe["judging_at"]   # 仮停止＝提出時刻
        if probe["last_wa"]:
            new["wa_at"] = probe["last_wa"]
    return new


def sig(st):
    """盤面再描画が要る状態の指紋。updated_at の変化では reload しない。
    submitted_at 必須: 再提出で仮停止時刻が進むのを盤面に反映するため。"""
    return (st.get("status"), st.get("task_id"), st.get("start"),
            st.get("grade"), bool(st.get("judging")), st.get("submitted_at"),
            st.get("wa_at"), st.get("tested_at"))


def commit(prev, new):
    changed = sig(prev) != sig(new) or not STATE.is_file()
    write_state(new)
    if changed:
        refresh_board()
        print(f"[stopwatch] {prev.get('status', '-')} -> {new['status']}"
              f"{' judging' if new.get('judging') else ''}"
              f" {new.get('task_id', '')}")
    return changed


def main():
    now = time.time()
    user = username()
    if not user:
        print("[stopwatch] no watchlist user", file=sys.stderr)
        return 1
    # プロセスロック: launchd と cp-go / oj キックの重なりで2インスタンスが
    # 同時に 10秒間隔ポーリングすると実効間隔が半減する（行儀違反）→ 後着は即退出。
    CACHE.mkdir(parents=True, exist_ok=True)
    plock = (CACHE / "poller.lock").open("w")
    try:
        fcntl.flock(plock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0
    prev = load_json(STATE, {}) or {}
    cand = latest_candidate()

    if not cand or now - cand["start"] > CAP_S:
        commit(prev, {"status": "idle", "updated_at": int(now)})
        return 0

    session = atcoder_session()
    new = build_state(cand, user, session, prev, now)
    commit(prev, new)

    # 臨戦態勢: oj test 直後(5分) or 判定中は 10秒間隔で見張る（認証経路のみ・
    # launchd 60秒枠内で完結）。提出→WJ発見→AC確定 が体感数秒〜十数秒になる。
    def hot(st, t):
        armed = st.get("tested_at") and t - st["tested_at"] < ARMED_WINDOW_S
        return st["status"] == "running" and (armed or st.get("judging"))

    t0 = time.time()
    while session and hot(new, time.time()) and time.time() - t0 < FAST_BUDGET_S:
        time.sleep(FAST_INTERVAL_S)
        prev = new
        new = build_state(cand, user, session, prev, time.time(), fast=True)
        commit(prev, new)
        if new["status"] != "running":
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
