#!/usr/bin/env python3
"""draft-v1 board data generator.

Reads ~/.cache/cp-dashboard/*.json and writes draft-data.js (window.DRAFT = {...})
next to this script. Called from bin/update.sh each cycle; safe to re-run manually.
"""
import json
import os
import statistics
import time
from datetime import date, datetime, timedelta
from pathlib import Path

CACHE = Path(os.environ.get("CP_DASH_CACHE", Path.home() / ".cache" / "cp-dashboard"))
OUT = Path(__file__).parent / "draft-data.js"
# solve-time baseline のデータセット。seed=x1nano の 288 不変シード（モジュール同梱）、
# live=このマシンのストップウォッチが貯める分（~/.cache）。両者同じ open→AC 定義。
SEED = Path(__file__).parent.parent / "data" / "solve_times_seed.jsonl"
LIVE = CACHE / "solve_times.jsonl"
BASELINE_MIN_N = 3          # grade をラダーに出す最小サンプル数
try:
    _wl = json.loads((Path(__file__).parent.parent / "watchlist.json").read_text())
except Exception:
    _wl = ["MeJamoLeo", "yiwiy9", "sinzyousan", "daikusutora3"]
USER = _wl[0]
RIVALS = _wl[1:]
DEADLINE = date(2026, 8, 19)


def load(name, default=None):
    p = CACHE / name
    if not p.exists():
        return default
    try:
        return json.loads(p.read_text())
    except Exception:
        return default


def meta_age_min(name, now):
    m = load(name)
    if not m or "fetched_at" not in m:
        return None
    try:
        t = datetime.fromisoformat(m["fetched_at"])
        return int((now - t.timestamp()) / 60)
    except Exception:
        return None


def _load_jsonl(path):
    try:
        return [json.loads(x) for x in path.read_text().splitlines() if x.strip()]
    except Exception:
        return []


def solve_baseline():
    """grade 別 solve-time 統計（分）を seed+live から計算。ライブのストップウォッチと
    同じ open→AC 定義。med/mean/max に加え Q1/Q3/四分位偏差(qd)を出す。
    n>=BASELINE_MIN_N の grade のみ、難易度順（Q 数字が小さいほど難＝先頭）。"""
    recs = _load_jsonl(SEED) + _load_jsonl(LIVE)
    by_grade = {}
    for r in recs:
        g, el = r.get("grade"), r.get("elapsed")
        if not g or not isinstance(el, (int, float)):
            continue
        by_grade.setdefault(g, []).append(el / 60.0)
    out = []
    total = 0
    for g, xs in by_grade.items():
        total += len(xs)
        if len(xs) < BASELINE_MIN_N:
            continue
        xs.sort()
        q1, med, q3 = statistics.quantiles(xs, n=4, method="inclusive")
        out.append({
            "g": g, "n": len(xs),
            "q1": round(q1, 1), "med": round(med, 1), "q3": round(q3, 1),
            "qd": round((q3 - q1) / 2, 1),        # 四分位偏差
            "mean": round(statistics.mean(xs), 1), "max": round(max(xs), 1),
        })

    def gkey(g):
        try:
            return int(g[1:])
        except Exception:
            return 99

    out.sort(key=lambda r: gkey(r["g"]))
    return {"grades": out, "n_total": total}


def day_of(epoch):
    return date.fromtimestamp(epoch)


def main():
    now = time.time()
    subs = load(f"submissions_{USER}.json", []) or []
    ratings = load(f"ratings_{USER}.json", []) or []
    novi = load("novisteps.json", {}) or {}
    models = load("problem_models.json", {}) or {}
    upcoming = load("upcoming_contests.json", []) or []

    subs.sort(key=lambda s: s["epoch_second"])
    acs = [s for s in subs if s["result"] == "AC"]

    def diff_of(pid):
        m = models.get(pid) or {}
        d = m.get("difficulty")
        return max(0, int(d)) if isinstance(d, (int, float)) else None

    # ---- streak ----
    ac_days = sorted({day_of(s["epoch_second"]) for s in acs})
    max_streak = cur = 0
    prev = None
    for d in ac_days:
        cur = cur + 1 if prev is not None and (d - prev).days == 1 else 1
        max_streak = max(max_streak, cur)
        prev = d
    today = date.today()
    streak = 0
    dset = set(ac_days)
    probe = today if today in dset else today - timedelta(days=1)
    while probe in dset:
        streak += 1
        probe -= timedelta(days=1)

    todays = [s for s in acs if day_of(s["epoch_second"]) == today]
    first_ac_today = (
        time.strftime("%H:%M", time.localtime(todays[0]["epoch_second"])) if todays else None
    )

    # ---- calendar (last 84 days) ----
    per_day = {}
    for s in acs:
        d = day_of(s["epoch_second"])
        e = per_day.setdefault(d, {"n": 0, "m": 0})
        e["n"] += 1
        dd = diff_of(s["problem_id"])
        if dd:
            e["m"] = max(e["m"], dd)
    cal = []
    for i in range(251, -1, -1):  # 36週分の在庫（表示側が枠幅に合わせて末尾から使う）
        d = today - timedelta(days=i)
        e = per_day.get(d, {"n": 0, "m": 0})
        cal.append({"d": d.isoformat(), "n": e["n"], "m": e["m"]})

    # ---- weeks (Monday start) ----
    monday = today - timedelta(days=today.weekday())

    def week_stats(start):
        end = start + timedelta(days=7)
        pids, dsum = set(), 0
        for s in acs:
            d = day_of(s["epoch_second"])
            if start <= d < end and s["problem_id"] not in pids:
                pids.add(s["problem_id"])
                dsum += diff_of(s["problem_id"]) or 0
        return {"ac": len(pids), "dsum": dsum}

    week = {"this": week_stats(monday), "last": week_stats(monday - timedelta(days=7))}

    # ---- rivals weekly race ----
    def rival_week(name):
        rs = load(f"submissions_{name}.json", []) or []
        pids = set()
        for s in rs:
            if s["result"] == "AC" and monday <= day_of(s["epoch_second"]) < monday + timedelta(days=7):
                pids.add(s["problem_id"])
        return len(pids)

    ghost_start = monday - timedelta(days=28)
    ghost = week_stats(ghost_start)["ac"]
    race = [{"name": USER, "ac": week["this"]["ac"], "self": True}]
    race += [{"name": r, "ac": rival_week(r)} for r in RIVALS]
    race.append({"name": "👻-28d", "ac": ghost, "ghost": True})

    # ---- perf / rating ----
    rated = [r for r in ratings if r.get("IsRated")]
    perfs = [r["Performance"] for r in rated]
    rhist = [
        {"e": int(datetime.fromisoformat(r["EndTime"]).timestamp()), "r": r["NewRating"]}
        for r in rated
    ]
    rating = rhist[-1]["r"] if rhist else 0
    pace = 0.0
    if len(rhist) >= 2:
        span = rhist[-1]["e"] - max(rhist[0]["e"], rhist[-1]["e"] - 56 * 86400)
        base = [p for p in rhist if p["e"] >= rhist[-1]["e"] - 56 * 86400]
        if len(base) >= 2 and span > 0:
            pace = (base[-1]["r"] - base[0]["r"]) / (span / 604800)
    perf_delta = None
    if len(perfs) >= 2:
        prev5 = perfs[-6:-1] or perfs[:-1]
        perf_delta = round(perfs[-1] - sum(prev5) / len(prev5))

    # ---- difficulty log (last 90 days, first-AC only) ----
    seen = set()
    dpoints = []
    for s in acs:
        if s["problem_id"] in seen:
            continue
        seen.add(s["problem_id"])
        if s["epoch_second"] < now - 90 * 86400:
            continue
        d = diff_of(s["problem_id"])
        if d is not None:
            dpoints.append({"e": s["epoch_second"], "d": d})
    dpoints = dpoints[-80:]

    # ---- submit hours (last 90 days) ----
    hours = [{"t": 0, "a": 0} for _ in range(24)]
    for s in subs:
        if s["epoch_second"] < now - 90 * 86400:
            continue
        h = time.localtime(s["epoch_second"]).tm_hour
        hours[h]["t"] += 1
        if s["result"] == "AC":
            hours[h]["a"] += 1

    # ---- submit scatter (last 28 days: day offset x hour) ----
    scatter = []
    start28 = today - timedelta(days=27)
    for s in subs:
        d = day_of(s["epoch_second"])
        if d < start28:
            continue
        lt = time.localtime(s["epoch_second"])
        scatter.append(
            {"x": (d - start28).days, "h": round(lt.tm_hour + lt.tm_min / 60, 2),
             "a": 1 if s["result"] == "AC" else 0, "d": diff_of(s["problem_id"])}
        )

    # ---- last sub ----
    last = subs[-1] if subs else None
    last_sub = (
        {
            "pid": last["problem_id"],
            "res": last["result"],
            "e": last["epoch_second"],
            "age_min": int((now - last["epoch_second"]) / 60),
        }
        if last
        else None
    )

    # ---- next ABC + ammo ----
    abcs = [
        c
        for c in upcoming
        if c.get("start_epoch", 0) > now
        and (c.get("type") == "ABC" or "Beginner" in c.get("title", ""))
    ]
    abcs.sort(key=lambda c: c["start_epoch"])
    next_abc = (
        {"id": abcs[0]["id"], "title": abcs[0]["title"], "e": abcs[0]["start_epoch"]}
        if abcs
        else None
    )
    ammo = 0
    d = today
    while d <= DEADLINE:
        if d.weekday() == 5:  # Saturday
            ammo += 1
        d += timedelta(days=1)

    # ---- freshness ----
    novi_age = None
    if novi.get("fetched_at"):
        try:
            novi_age = int((now - datetime.fromisoformat(novi["fetched_at"]).timestamp()) / 60)
        except Exception:
            pass
    fresh = {
        "kenkoooo_min": meta_age_min(f"submissions_{USER}.meta.json", now),
        "rating_min": meta_age_min(f"ratings_{USER}.meta.json", now),
        "novi_min": novi_age,
        "novi_cookie_expired": bool(novi.get("cookie_expired")),
    }

    # ---- novisteps topic matrix ----
    ORDER = {"ac": 0, "ac_with_editorial": 1, "wa": 2, "ns": 3}
    tot = {"ac": 0, "ed": 0, "wa": 0, "ns": 0}
    topics = []
    for wb in (novi.get("workbooks") or {}).values():
        tasks = wb.get("tasks", [])
        if not tasks:
            continue
        c = {"ac": 0, "ed": 0, "wa": 0, "ns": 0}
        for t in tasks:
            k = {"ac": "ac", "ac_with_editorial": "ed", "wa": "wa", "ns": "ns"}[t["status"]]
            c[k] += 1
            tot[k] += 1

        def gnum(t):
            g = t.get("grade") or "Q9"
            try:
                return int(g[1:])
            except Exception:
                return 9

        by_grade = {}
        for t in tasks:
            gn = gnum(t)
            e = by_grade.setdefault(gn, {"a": 0, "e": 0, "w": 0, "t": 0})
            e["t"] += 1
            if t["status"] == "ac":
                e["a"] += 1
            elif t["status"] == "ac_with_editorial":
                e["e"] += 1
            elif t["status"] == "wa":
                e["w"] += 1
        # 級セル: Q大(易)→Q小(難)。 [gradeNum, 自力AC, 解説AC, 挑戦中, total]
        grades = [[gn, v["a"], v["e"], v["w"], v["t"]] for gn, v in sorted(by_grade.items(), reverse=True)]
        done = c["ac"] + c["ed"]
        topics.append(
            {
                "title": wb.get("title", "?")[:10],
                "grades": grades,
                "done": done,
                "total": len(tasks),
                "active": c["wa"] > 0,
            }
        )
    topics.sort(key=lambda t: (-(t["done"] / t["total"]), -t["total"]))

    # ---- records ----
    best = {"diff": 0, "pid": None}
    for s in acs:
        d = diff_of(s["problem_id"])
        if d and d > best["diff"]:
            best = {"diff": d, "pid": s["problem_id"]}

    # ---- solve stopwatch (#36) — state maintained by upstream/stopwatch_poll.py ----
    sw = load("stopwatch.json") or {}
    stopwatch = None
    if sw.get("status") in ("running", "frozen") and sw.get("start"):
        stopwatch = {
            "status": sw["status"],
            "task_id": sw.get("task_id"),
            "grade": sw.get("grade"),
            "start": sw["start"],
            "elapsed": sw.get("elapsed"),
            "judging": bool(sw.get("judging")),
            "submitted_at": sw.get("submitted_at"),
            "wa_at": sw.get("wa_at"),
            "tested_at": sw.get("tested_at"),
        }

    draft = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "now": int(now),
        "user": USER,
        "hud": {
            "rating": rating,
            "streak": streak,
            "max_streak": max_streak,
            "first_ac_today": first_ac_today,
            "ac_total": len({s["problem_id"] for s in acs}),
        },
        "next_abc": next_abc,
        "ammo": ammo,
        "deadline": DEADLINE.isoformat(),
        "last_sub": last_sub,
        "fresh": fresh,
        "week": week,
        "race": race,
        "perfs": perfs,
        "perf_delta": perf_delta,
        "rhist": rhist,
        "pace_week": round(pace, 1),
        "dpoints": dpoints,
        "hours": hours,
        "cal": cal,
        "scatter": scatter,
        "novi": {"totals": tot, "topics": topics, "user": novi.get("user")},
        "records": {"max_diff": best["diff"], "max_diff_pid": best["pid"], "max_streak": max_streak},
        "stopwatch": stopwatch,
        "solveRef": solve_baseline(),
    }
    OUT.write_text("window.DRAFT = " + json.dumps(draft, ensure_ascii=False) + ";\n")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)  streak={streak} rating={rating} "
          f"week={week['this']['ac']}AC ammo={ammo}")


if __name__ == "__main__":
    main()
