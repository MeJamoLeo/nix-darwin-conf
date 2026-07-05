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

elapsed = ac_epoch - start, so polling lag never distorts the frozen value.

Invocation:
  - launchd every 60s (com.treo.cp-dashboard-stopwatch). No-op when idle.
  - cp-go fires one pass right after oj download so the board reacts in seconds.

State:   ~/.cache/cp-dashboard/stopwatch.json   (read by gen-draft-data.py)
Dataset: ~/.cache/cp-dashboard/solve_times.jsonl (frozen sessions, 30s–4h
         filter as in the n=288 snapshot; merge with x1nano analyze later)
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
CAP_S = 4 * 3600
MIN_S = 30


def load_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except Exception:
        return default


def username():
    wl = load_json(ROOT / "watchlist.json", [])
    return wl[0] if wl else None


def latest_candidate():
    """Most recently opened problem within the 4h window, or None."""
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


ATCODER_KEYCHAIN_SERVICE = "atcoder-revel-session"
FIXTIME_RE = re.compile(r'<time class=["\']fixtime fixtime-second["\']>([^<]+)</time>')


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


def first_ac_epoch_atcoder(user, contest, task_id, start, session):
    """速報経路: 公式の提出一覧（要ログイン）から初ACを引く。
    Returns (epoch|None, authoritative) — authoritative=False は認証切れ/取得失敗
    （kenkoooo へフォールバック）、True の epoch=None は「まだACが無い」の確定."""
    url = (f"{ATCODER_BASE}/contests/{contest}/submissions"
           f"?f.Task={task_id}&f.User={user}&f.Status=AC")
    raw = _fetch(url, headers={"Cookie": f"REVEL_SESSION={session}"})
    if raw is None:
        return None, False
    html = raw.decode("utf-8", "replace")
    if "<title>Sign In" in html:
        print("[stopwatch] atcoder cookie expired — run cp-login", file=sys.stderr)
        return None, False
    # クエリフィルタを信用せず行単位で task/user/AC を検証してから時刻を取る
    epochs = []
    suspect = False   # AC行はあるのに時刻が取れない＝ページ構造変化の兆候
    for row in html.split("<tr>"):
        if f"/contests/{contest}/tasks/{task_id}" not in row:
            continue
        if f"/users/{user}" not in row or ">AC</span>" not in row:
            continue
        m = FIXTIME_RE.search(row)
        if not m:
            suspect = True
            continue
        try:
            epochs.append(int(datetime.strptime(
                m.group(1).strip(), "%Y-%m-%d %H:%M:%S%z").timestamp()))
        except ValueError:
            suspect = True
            continue
    acs = [e for e in epochs if e >= int(start)]
    if acs:
        return min(acs), True
    if suspect:
        # 「無い」と断定せず kenkoooo に回す（構造変化で両経路が死ぬのを防ぐ）
        print("[stopwatch] atcoder page structure changed? — fallback",
              file=sys.stderr)
        return None, False
    return None, True


def first_ac_epoch(user, contest, task_id, start):
    """Earliest AC at/after start.
    Order: local cache (offline) → AtCoder 公式 (速報・要 cookie) → kenkoooo."""
    subs = load_json(CACHE / f"submissions_{user}.json", []) or []
    acs = [s["epoch_second"] for s in subs
           if s.get("problem_id") == task_id and s.get("result") == "AC"
           and s.get("epoch_second", 0) >= int(start)]
    if acs:
        return min(acs)
    session = atcoder_session()
    if session:
        ac, authoritative = first_ac_epoch_atcoder(
            user, contest, task_id, start, session)
        if authoritative:
            return ac          # 公式の「無い」は kenkoooo より新しい＝これで確定
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

    flock: the launchd 60s timer and the cp-go kick can run concurrently;
    without the lock both pass the dedupe read and double-append."""
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


def load_json_str(s):
    try:
        return json.loads(s)
    except Exception:
        return None


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


def main():
    now = time.time()
    user = username()
    if not user:
        print("[stopwatch] no watchlist user", file=sys.stderr)
        return 1
    prev = load_json(STATE, {}) or {}
    cand = latest_candidate()

    new = {"status": "idle", "updated_at": int(now)}
    if cand and now - cand["start"] <= CAP_S:
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
            new = prev
        else:
            ac = first_ac_epoch(user, cand["contest"], cand["task_id"],
                                cand["start"])
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
                        print(f"[stopwatch] dataset += {cand['task_id']} "
                              f"{elapsed}s")
            else:
                new = {**base, "status": "running"}

    changed = (
        prev.get("status", "idle") != new["status"]
        or prev.get("task_id") != new.get("task_id")
        or prev.get("start") != new.get("start")
    )
    if changed or not STATE.is_file():
        write_state(new)
        refresh_board()
        print(f"[stopwatch] {prev.get('status', '-')} -> {new['status']}"
              f" {new.get('task_id', '')}")
    else:
        # keep updated_at fresh without triggering a board reload
        write_state(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
