#!/usr/bin/env python3
"""Fetch AtCoder stats and write JSON for the CP dashboard.

Data sources:
  1. atcoder.jp /users/{user}/history/json — rating history (official, no auth)
  2. atcoder.jp /contests/?lang=ja — upcoming contests (HTML scraping)
  3. kenkoooo.com AtCoder Problems API — submissions, difficulties (may 403)
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


# Use system local timezone instead of hardcoded JST
try:
    LOCAL_TZ = datetime.now().astimezone().tzinfo
except Exception:
    LOCAL_TZ = timezone(timedelta(hours=9))  # fallback to JST

KENKOOOO_BASE = "https://kenkoooo.com/atcoder"
ATCODER_BASE = "https://atcoder.jp"

RATING_LABELS: list[tuple[int, str]] = [
    (2800, "赤"),
    (2400, "橙"),
    (2000, "黄"),
    (1600, "青"),
    (1200, "水色"),
    (800, "緑"),
    (400, "茶色"),
    (0, "灰"),
]

# Cache TTL in seconds
TTL_RATINGS = 3600  # 1h
TTL_SUBMISSIONS = 0  # incremental
TTL_DIFFICULTIES = 86400  # 24h
TTL_PROBLEMS = 86400  # 24h
TTL_CONTESTS = 21600  # 6h


@dataclass(frozen=True)
class Config:
    username: str
    cache_dir: Path
    output_path: Path


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

def _cache_path(cache_dir: Path, key: str) -> Path:
    return cache_dir / f"{key}.json"


def _meta_path(cache_dir: Path, key: str) -> Path:
    return cache_dir / f"{key}.meta.json"


def read_cache(cache_dir: Path, key: str, ttl: int) -> Any | None:
    path = _cache_path(cache_dir, key)
    meta = _meta_path(cache_dir, key)
    if not path.exists() or not meta.exists():
        return None
    try:
        m = json.loads(meta.read_text())
        if time.time() - m.get("fetched_at", 0) > ttl:
            return None
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        path.unlink(missing_ok=True)
        meta.unlink(missing_ok=True)
        return None


def read_cache_raw(cache_dir: Path, key: str) -> Any | None:
    """Read cache ignoring TTL (stale fallback)."""
    path = _cache_path(cache_dir, key)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def write_cache(cache_dir: Path, key: str, data: Any) -> None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    _cache_path(cache_dir, key).write_text(
        json.dumps(data, ensure_ascii=False)
    )
    _meta_path(cache_dir, key).write_text(
        json.dumps({"fetched_at": time.time()})
    )


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def _fetch(url: str, retries: int = 1, headers: dict | None = None) -> bytes | None:
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": (
                        "Mozilla/5.0 (X11; Linux x86_64) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/120.0.0.0 Safari/537.36"
                    ),
                    "Accept": "application/json, text/html, */*",
                    "Accept-Encoding": "gzip",
                    **(headers or {}),
                },
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    data = gzip.decompress(data)
                return data
        except (urllib.error.URLError, OSError) as e:
            if attempt < retries:
                time.sleep(3)
                continue
            print(f"[fetch_stats] ERROR {url}: {e}", file=sys.stderr)
            return None


def _fetch_json(url: str, retries: int = 1) -> Any | None:
    raw = _fetch(url, retries)
    if raw is None:
        return None
    try:
        return json.loads(raw.decode())
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"[fetch_stats] JSON parse error {url}: {e}", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# Data fetchers
# ---------------------------------------------------------------------------

def fetch_rating_history(cfg: Config) -> list[dict]:
    """Fetch from official AtCoder API."""
    cache_key = f"ratings_{cfg.username}"
    cached = read_cache(cfg.cache_dir, cache_key, TTL_RATINGS)
    if cached is not None:
        return cached

    url = f"{ATCODER_BASE}/users/{cfg.username}/history/json"
    data = _fetch_json(url)
    if data is None:
        return read_cache_raw(cfg.cache_dir, cache_key) or []
    write_cache(cfg.cache_dir, cache_key, data)
    return data


def fetch_submissions_kenkoooo(cfg: Config) -> list[dict]:
    """Fetch submissions via kenkoooo API (may fail with 403)."""
    cache_key = f"submissions_{cfg.username}"
    path = _cache_path(cfg.cache_dir, cache_key)

    cached: list[dict] = []
    last_epoch = 0
    if path.exists():
        try:
            cached = json.loads(path.read_text())
            if cached:
                last_epoch = max(s.get("epoch_second", 0) for s in cached) + 1
        except (json.JSONDecodeError, OSError):
            cached = []

    from_second = last_epoch
    new_subs: list[dict] = []

    while True:
        url = (
            f"{KENKOOOO_BASE}/atcoder-api/v3/user/submissions"
            f"?user={cfg.username}&from_second={from_second}"
        )
        batch = _fetch_json(url)
        if batch is None:
            break
        if isinstance(batch, dict) and "message" in batch:
            # API returned error (e.g. {"message": "Forbidden"})
            print(
                f"[fetch_stats] kenkoooo API error: {batch['message']}",
                file=sys.stderr,
            )
            break
        new_subs.extend(batch)
        if len(batch) < 500:
            break
        from_second = max(s["epoch_second"] for s in batch) + 1
        time.sleep(1)

    if new_subs:
        all_subs = cached + new_subs
        write_cache(cfg.cache_dir, cache_key, all_subs)
        return all_subs
    return cached


def fetch_difficulties_kenkoooo(cfg: Config) -> dict[str, Any]:
    cache_key = "problem_models"
    cached = read_cache(cfg.cache_dir, cache_key, TTL_DIFFICULTIES)
    if cached is not None:
        return cached

    url = f"{KENKOOOO_BASE}/resources/problem-models.json"
    data = _fetch_json(url)
    if data is None or (isinstance(data, dict) and "message" in data):
        return read_cache_raw(cfg.cache_dir, cache_key) or {}
    write_cache(cfg.cache_dir, cache_key, data)
    return data


def fetch_problems_kenkoooo(cfg: Config) -> list[dict]:
    cache_key = "problems"
    cached = read_cache(cfg.cache_dir, cache_key, TTL_PROBLEMS)
    if cached is not None:
        return cached

    url = f"{KENKOOOO_BASE}/resources/problems.json"
    data = _fetch_json(url)
    if data is None or (isinstance(data, dict) and "message" in data):
        return read_cache_raw(cfg.cache_dir, cache_key) or []
    write_cache(cfg.cache_dir, cache_key, data)
    return data


def fetch_upcoming_contests(cfg: Config) -> list[dict]:
    """Scrape upcoming contests from atcoder.jp/contests."""
    cache_key = "upcoming_contests"
    cached = read_cache(cfg.cache_dir, cache_key, TTL_CONTESTS)
    if cached is not None:
        return cached

    raw = _fetch(f"{ATCODER_BASE}/contests/?lang=ja")
    if raw is None:
        return read_cache_raw(cfg.cache_dir, cache_key) or []

    html = raw.decode("utf-8", errors="replace")
    contests = _parse_contests_html(html)
    if contests:
        write_cache(cfg.cache_dir, cache_key, contests)
    return contests


def _parse_contests_html(html: str) -> list[dict]:
    """Extract upcoming contests from the contests page HTML."""
    contests: list[dict] = []
    now = time.time()

    # Find all contest rows: <time>...</time> paired with <a href="/contests/xxx">
    # Pattern: time tag followed by contest link in the same table row
    time_pattern = re.compile(
        r"<time[^>]*>(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{4})</time>"
    )
    link_pattern = re.compile(
        r'<a href="/contests/([^"]+)">([^<]+)</a>'
    )
    rated_pattern = re.compile(
        r"(~ \d+|All)"
    )

    # Split by table rows
    rows = html.split("<tr")
    for row in rows:
        times = time_pattern.findall(row)
        links = link_pattern.findall(row)
        if not times or not links:
            continue

        # Take the first time (start) and last link (contest name)
        time_str = times[0]
        try:
            dt = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S%z")
            start_epoch = int(dt.timestamp())
        except ValueError:
            continue

        # Skip past contests
        if start_epoch < now:
            continue

        # Find contest link (skip timeanddate.com links)
        contest_id = ""
        contest_title = ""
        for cid, ctitle in links:
            if "timeanddate" not in cid:
                contest_id = cid
                contest_title = ctitle
                break
        if not contest_id:
            continue

        # Skip Daily Training and non-regular contests
        if "adt_" in contest_id or "masters" in contest_id or "awc" in contest_id:
            continue

        # Determine type
        if contest_id.startswith("abc"):
            ctype = "ABC"
            rated = "〜1999"
        elif contest_id.startswith("arc"):
            ctype = "ARC"
            rated = "〜2799"
        elif contest_id.startswith("agc"):
            ctype = "AGC"
            rated = "All"
        elif contest_id.startswith("ahc"):
            ctype = "AHC"
            rated = "All"
        else:
            ctype = "Other"
            rated = ""

        is_rated = ctype in ("ABC", "AHC")

        # Duration: look for two <time> tags (start + end)
        duration = 6000  # default 100min
        if len(times) >= 2:
            try:
                dt_end = datetime.strptime(times[1], "%Y-%m-%d %H:%M:%S%z")
                duration = int(dt_end.timestamp()) - start_epoch
            except ValueError:
                pass

        contests.append({
            "id": contest_id,
            "title": contest_title,
            "type": ctype,
            "start_epoch": start_epoch,
            "duration_seconds": duration,
            "rated_range": rated,
            "is_rated_for_user": is_rated,
        })

    contests.sort(key=lambda x: x["start_epoch"])
    return contests[:8]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _rating_label(rating: int) -> str:
    for threshold, label in RATING_LABELS:
        if rating >= threshold:
            return label
    return "灰"


def _rating_band(rating: int) -> tuple[int, int]:
    for i, (threshold, _) in enumerate(RATING_LABELS):
        if rating >= threshold:
            upper = RATING_LABELS[i - 1][0] if i > 0 else 9999
            return threshold, upper
    return 0, 400


def _epoch_to_jst_date(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, tz=LOCAL_TZ).strftime("%Y-%m-%d")


def _today_jst() -> str:
    return datetime.now(LOCAL_TZ).strftime("%Y-%m-%d")


def _ac_problems(submissions: list[dict]) -> dict[str, dict]:
    ac_map: dict[str, dict] = {}
    for s in sorted(submissions, key=lambda x: x.get("epoch_second", 0)):
        pid = s.get("problem_id", "")
        if s.get("result") == "AC" and pid not in ac_map:
            ac_map[pid] = s
    return ac_map


def _color_label(diff: int) -> str:
    if diff < 400:
        return "灰"
    if diff < 800:
        return "茶"
    if diff < 1200:
        return "緑"
    if diff < 1600:
        return "水"
    if diff < 2000:
        return "青"
    if diff < 2400:
        return "黄"
    if diff < 2800:
        return "橙"
    return "赤"


def _guess_tag(problem_id: str, contest_id: str, difficulty: float) -> str:
    pid = problem_id.lower()
    cid = contest_id.lower()

    if "edpc" in cid or "dp" in pid:
        return "DP"
    if pid.endswith("_a") or pid.endswith("_b"):
        return "実装"
    if difficulty < 400:
        return "実装"
    if difficulty < 800:
        return "累積和"
    return "アルゴリズム"


def _load_tag_overrides() -> dict[str, str]:
    path = Path.home() / ".cp" / "tag_overrides.json"
    if path.exists():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {}


# ---------------------------------------------------------------------------
# Transformers
# ---------------------------------------------------------------------------

def build_hud(
    submissions: list[dict],
    ratings: list[dict],
    streak_days: int,
    max_streak: int,
) -> dict:
    ac_map = _ac_problems(submissions)
    total = len(submissions)
    wa_count = sum(1 for s in submissions if s.get("result") == "WA")
    wa_rate = wa_count / total if total > 0 else 0.0

    current_rating = ratings[-1]["NewRating"] if ratings else 0

    today = _today_jst()
    today_acs = [
        s for s in submissions
        if _epoch_to_jst_date(s.get("epoch_second", 0)) == today
        and s.get("result") == "AC"
    ]
    # 今日の最初のAC時刻 (5時以降 = 起床後の提出のみ)
    MORNING_START_HOUR = 5
    first_ac_today = ""
    if today_acs:
        morning_acs = [
            s for s in today_acs
            if datetime.fromtimestamp(
                s["epoch_second"], tz=LOCAL_TZ
            ).hour >= MORNING_START_HOUR
        ]
        if morning_acs:
            earliest = min(morning_acs, key=lambda s: s["epoch_second"])
            first_ac_today = datetime.fromtimestamp(
                earliest["epoch_second"], tz=LOCAL_TZ
            ).strftime("%H:%M")

    # Average first AC time (last 30 days, 5時以降のみ)
    thirty_days_ago = datetime.now(LOCAL_TZ) - timedelta(days=30)
    by_date: dict[str, list[dict]] = {}
    for s in submissions:
        if s.get("result") != "AC":
            continue
        dt = datetime.fromtimestamp(s["epoch_second"], tz=LOCAL_TZ)
        if dt >= thirty_days_ago and dt.hour >= MORNING_START_HOUR:
            by_date.setdefault(dt.strftime("%Y-%m-%d"), []).append(s)
    daily_first_minutes: list[int] = []
    for subs in by_date.values():
        earliest = min(subs, key=lambda s: s["epoch_second"])
        dt = datetime.fromtimestamp(earliest["epoch_second"], tz=LOCAL_TZ)
        daily_first_minutes.append(dt.hour * 60 + dt.minute)
    avg_first_ac = ""
    if daily_first_minutes:
        avg = sum(daily_first_minutes) // len(daily_first_minutes)
        avg_first_ac = f"{avg // 60}:{avg % 60:02d}"

    return {
        "rating": current_rating,
        "rank_label": _rating_label(current_rating),
        "streak_days": streak_days,
        "max_streak": max_streak,
        "ac_count": len(ac_map),
        "wa_rate": round(wa_rate, 3),
        "first_ac_today": first_ac_today,
        "avg_first_ac": avg_first_ac,
    }


def build_player_status(
    submissions: list[dict],
    ratings: list[dict],
    difficulties: dict[str, Any],
    streak_days: int,
    max_streak: int,
) -> dict:
    current_rating = ratings[-1]["NewRating"] if ratings else 0
    band_low, band_high = _rating_band(current_rating)
    progress = (
        (current_rating - band_low) / (band_high - band_low)
        if band_high > band_low
        else 0
    )

    ac_map = _ac_problems(submissions)
    level = len(ac_map) // 10

    today = _today_jst()
    today_acs: list[dict] = []
    seen: set[str] = set()
    for s in submissions:
        if s.get("result") != "AC":
            continue
        if _epoch_to_jst_date(s.get("epoch_second", 0)) != today:
            continue
        pid = s.get("problem_id", "")
        if pid in seen:
            continue
        seen.add(pid)
        diff = difficulties.get(pid, {}).get("difficulty") or 0
        if diff < 0:
            diff = 0
        today_acs.append({
            "problem_id": pid,
            "difficulty": round(diff),
            "xp": round(max(diff, 100)),
        })

    return {
        "rating": current_rating,
        "rating_min": band_low,
        "rating_max": band_high,
        "rating_progress": round(progress, 3),
        "level": level,
        "today_xp": sum(a["xp"] for a in today_acs),
        "streak_days": streak_days,
        "max_streak": max_streak,
        "today_acs": today_acs,
    }


def build_daily_volume(
    submissions: list[dict],
    difficulties: dict[str, Any],
    days: int = 30,
) -> dict:
    today_str = _today_jst()
    today_dt = datetime.strptime(today_str, "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
    cutoff = (today_dt - timedelta(days=days - 1)).strftime("%Y-%m-%d")

    by_day: dict[str, dict[str, float]] = {}
    for s in submissions:
        if s.get("result") != "AC":
            continue
        date = _epoch_to_jst_date(s.get("epoch_second", 0))
        if date < cutoff:
            continue
        pid = s.get("problem_id", "")
        if not pid:
            continue
        model = difficulties.get(pid)
        if not model or model.get("difficulty") is None:
            continue
        bucket = by_day.setdefault(date, {})
        if pid not in bucket:
            bucket[pid] = float(model["difficulty"])

    result: list[dict] = []
    for i in range(days):
        date = (today_dt - timedelta(days=days - 1 - i)).strftime("%Y-%m-%d")
        raws = list(by_day.get(date, {}).values())
        clamped = [max(0, int(round(r))) for r in raws]
        clamped_sorted = sorted(clamped, reverse=True)
        sum_xp = sum(max(c, 100) for c in clamped) if clamped else 0
        max_diff = clamped_sorted[0] if clamped_sorted else 0
        top3_sum = sum(clamped_sorted[:3])
        # perf uses raw diff (negative allowed) so easy problems aren't overweighted
        perf = round(sum(2 ** (r / 400) for r in raws), 1) if raws else 0.0
        by_color: dict[str, int] = {
            c: 0 for c in ["灰", "茶", "緑", "水", "青", "黄", "橙", "赤"]
        }
        for c in clamped:
            by_color[_color_label(c)] += 1
        result.append({
            "date": date,
            "count": len(raws),
            "sum_xp": sum_xp,
            "max_diff": max_diff,
            "top3_sum": top3_sum,
            "perf": perf,
            "by_color": by_color,
        })
    return {"days": result}


def build_wa_queue(
    submissions: list[dict],
    difficulties: dict[str, Any],
    problems_list: list[dict],
    tag_overrides: dict[str, str],
    current_rating: int = 0,
) -> list[dict]:
    problems_map = {p["id"]: p for p in problems_list}
    # 実力から離れすぎた問題を除外: 解ける確率≈43% = 現レート+100
    diff_cap = current_rating + 100 if current_rating > 0 else 9999

    by_problem: dict[str, list[dict]] = {}
    for s in submissions:
        by_problem.setdefault(s.get("problem_id", ""), []).append(s)

    # 1年以上前のWAは復習対象外
    one_year_ago = time.time() - 365 * 86400

    queue: list[dict] = []
    for pid, subs in by_problem.items():
        has_ac = any(s.get("result") == "AC" for s in subs)
        wa_count = sum(1 for s in subs if s.get("result") == "WA")
        if wa_count > 0 and not has_ac:
            diff = difficulties.get(pid, {}).get("difficulty") or 0
            if diff < 0:
                diff = 0
            if diff > diff_cap:
                continue
            cid = problems_map.get(pid, {}).get("contest_id", "")
            tag = tag_overrides.get(pid, _guess_tag(pid, cid, diff))
            last_wa = max(
                (s["epoch_second"] for s in subs if s.get("result") == "WA"),
                default=0,
            )
            if last_wa < one_year_ago:
                continue
            queue.append({
                "problem_id": pid,
                "wa_count": wa_count,
                "tag": tag,
                "difficulty": round(diff),
                "last_wa_epoch": last_wa,
            })

    queue.sort(key=lambda x: (-x["wa_count"], -x["difficulty"]))
    return queue[:8]


def _merge_local_ac(ac_map: dict[str, dict], difficulties: dict[str, Any]) -> None:
    """Merge local AC records (from cp-finish) into ac_map for immediate display."""
    local_path = Path.home() / "cp" / "local_ac.json"
    if not local_path.exists():
        return
    try:
        local = json.loads(local_path.read_text())
    except (json.JSONDecodeError, OSError):
        return
    for entry in local:
        pid = entry.get("problem_id", "")
        if pid and pid not in ac_map:
            ac_map[pid] = {"epoch_second": entry["epoch"], "problem_id": pid}


def build_difficulty_log(
    submissions: list[dict],
    difficulties: dict[str, Any],
    ratings: list[dict],
) -> dict:
    ac_map = _ac_problems(submissions)
    _merge_local_ac(ac_map, difficulties)
    current_rating = ratings[-1]["NewRating"] if ratings else 0

    points: list[dict] = []
    for pid, s in ac_map.items():
        diff = difficulties.get(pid, {}).get("difficulty") or 0
        if diff < 0:
            diff = 0
        points.append({
            "epoch": s["epoch_second"],
            "difficulty": round(diff),
        })
    points.sort(key=lambda x: x["epoch"])

    now = time.time()
    # 全期間のデータを使用（ACがない期間でもグラフを表示）
    recent_points = points

    # Weekly difficulty sums (棒グラフ用)
    weekly_diff_sums: list[dict] = []
    if recent_points:
        week_sums: dict[int, dict] = {}
        first_epoch = recent_points[0]["epoch"]
        for p in recent_points:
            wk = (p["epoch"] - first_epoch) // (7 * 86400)
            wk_epoch = first_epoch + wk * 7 * 86400
            if wk_epoch not in week_sums:
                week_sums[wk_epoch] = {
                    "epoch": wk_epoch, "sum": 0, "count": 0,
                }
            week_sums[wk_epoch]["sum"] += p["difficulty"]
            week_sums[wk_epoch]["count"] += 1
        weekly_diff_sums = sorted(
            week_sums.values(), key=lambda x: x["epoch"],
        )

    # --- Prediction model v2.1 ---
    import math

    # Band targets (monthly diff needed, realistic time estimates)
    BAND_TARGETS = [
        (0,    4000,  "A/B/C"),    # gray→brown
        (400,  7500,  "C/D"),      # brown→green
        (800,  12000, "D/E"),      # green→cyan
        (1200, 18000, "E/F"),      # cyan→blue
        (1600, 25000, "E/F"),      # blue→yellow
    ]

    def _smooth_efficiency(rating: int) -> float:
        """Smooth exponential decay of efficiency by rating.

        Calibrated: rating 0 → ~0.025, rating 800 → ~0.004,
        rating 1600 → ~0.001. No discontinuities at band boundaries.
        """
        return 0.03 * math.exp(-rating / 550)

    def _convergence_rating(perfs: list[int]) -> int:
        """AtCoder's actual rating convergence using exponential decay 0.9.

        Rating ≈ weighted_avg(perfs, decay=0.9) - 1200 * correction(n)
        """
        n = len(perfs)
        if n == 0:
            return 0
        weighted_sum = 0.0
        weight_sum = 0.0
        for i, p in enumerate(perfs):
            w = 0.9 ** (n - 1 - i)
            weighted_sum += w * p
            weight_sum += w
        weighted_avg = weighted_sum / weight_sum
        # Correction factor (negligible for n > 50)
        correction = (math.sqrt(1 - 0.9 ** (2 * n))) / (1 - 0.9 ** n) - 1
        return round(weighted_avg - 1200 * correction)

    # Average weekly diff from recent weeks
    avg_weekly_diff = 0
    if weekly_diff_sums:
        recent_weeks = weekly_diff_sums[-10:]
        avg_weekly_diff = round(
            sum(w["sum"] for w in recent_weeks) / len(recent_weeks)
        )

    # Perf-based convergence (for users with 10+ contests)
    perf_projection: dict | None = None
    if len(ratings) >= 10:
        all_perfs = [r["Performance"] for r in ratings]
        recent_perfs = [r["Performance"] for r in ratings[-20:]]
        perf_projection = {
            "avg_perf_recent": round(
                sum(recent_perfs) / len(recent_perfs)
            ),
            "convergence_rating": _convergence_rating(all_perfs),
        }

    # Efficiency for current rating
    eff = _smooth_efficiency(current_rating)

    # Effort-based projections
    projections: list[dict] = []
    cur_epoch = now
    if ratings:
        last_ep = ratings[-1].get("EndTime", 0)
        if isinstance(last_ep, str):
            try:
                last_ep = int(
                    datetime.fromisoformat(last_ep).timestamp()
                )
            except ValueError:
                last_ep = int(now)
        cur_epoch = last_ep

    for scenario, multiplier in [
        ("optimistic", 1.5),
        ("maintain", 1.0),
        ("pessimistic", 0.3),
    ]:
        weekly_diff = round(avg_weekly_diff * multiplier)
        proj_points = []
        cur_r = current_rating
        for week in range(1, 14):
            future_epoch = cur_epoch + week * 7 * 86400
            # Smooth efficiency recalculated as rating changes
            weekly_gain = weekly_diff * _smooth_efficiency(cur_r) / 4.33
            cur_r = max(0, min(2800, cur_r + weekly_gain))
            proj_points.append({
                "epoch": round(future_epoch),
                "rating": round(cur_r),
            })
        projections.append({
            "scenario": scenario,
            "weekly_diff": weekly_diff,
            "points": proj_points,
        })

    # Band target: what's needed for next color
    band_target = None
    next_color_rating = 400  # default
    for floor, monthly_diff, focus in BAND_TARGETS:
        if current_rating >= floor:
            band_target = {
                "monthly_diff": monthly_diff,
                "weekly_diff": round(monthly_diff / 4.33),
                "focus": focus,
            }
            # Find next color boundary
            idx = [b[0] for b in BAND_TARGETS].index(floor)
            if idx + 1 < len(BAND_TARGETS):
                next_color_rating = BAND_TARGETS[idx + 1][0]
            else:
                next_color_rating = floor + 400

    # Estimated months to next color at current pace
    remaining = next_color_rating - current_rating
    months_to_next = None
    if avg_weekly_diff > 0 and remaining > 0:
        weekly_gain = avg_weekly_diff * eff / 4.33
        if weekly_gain > 0:
            weeks_needed = remaining / weekly_gain
            months_to_next = round(weeks_needed / 4.33, 1)

    # Required weekly diff to reach next color in 3/6 months
    pace_targets = {}
    for months in [3, 6]:
        weeks = months * 4.33
        if remaining > 0 and eff > 0:
            needed_weekly = remaining / (weeks * eff / 4.33)
            pace_targets[f"{months}mo"] = round(needed_weekly)

    result: dict = {
        "points": recent_points,
        "weekly_diff_sums": weekly_diff_sums,
        "current_rating": current_rating,
        "avg_weekly_diff": avg_weekly_diff,
        "band_efficiency": round(eff, 5),
        "band_target": band_target,
        "next_color_rating": next_color_rating,
        "months_to_next": months_to_next,
        "pace_targets": pace_targets,
        "projections": projections,
    }
    if perf_projection:
        result["perf_projection"] = perf_projection
    return result


def build_language_stats(submissions: list[dict]) -> list[dict]:
    """Count unique ACs per programming language."""
    ac_map = _ac_problems(submissions)
    # Map problem_id to language from first AC submission
    lang_count: dict[str, int] = {}
    for pid, s in ac_map.items():
        lang = s.get("language", "Unknown")
        # Normalize language names
        if "Python" in lang or "PyPy" in lang:
            lang = "Python"
        elif "C++" in lang:
            lang = "C++"
        elif "Rust" in lang:
            lang = "Rust"
        elif "Java" in lang:
            lang = "Java"
        elif "Go" in lang:
            lang = "Go"
        elif "Ruby" in lang:
            lang = "Ruby"
        elif "JavaScript" in lang or "Node" in lang:
            lang = "JavaScript"
        elif "TypeScript" in lang or "Deno" in lang:
            lang = "TypeScript"
        elif "C#" in lang:
            lang = "C#"
        elif "Kotlin" in lang:
            lang = "Kotlin"
        lang_count[lang] = lang_count.get(lang, 0) + 1

    result = sorted(
        [{"lang": k, "count": v} for k, v in lang_count.items()],
        key=lambda x: -x["count"],
    )
    return result[:8]


def build_tag_ac_rate(
    submissions: list[dict],
    problems_list: list[dict],
    difficulties: dict[str, Any],
    tag_overrides: dict[str, str],
) -> list[dict]:
    problems_map = {p["id"]: p for p in problems_list}

    # Track per-problem per-tag: was it AC'd?
    problem_results: dict[str, dict[str, bool]] = {}  # tag -> {pid: ac?}
    for s in submissions:
        pid = s.get("problem_id", "")
        cid = problems_map.get(pid, {}).get("contest_id", "")
        diff = difficulties.get(pid, {}).get("difficulty") or 0
        if diff < 0:
            diff = 0
        tag = tag_overrides.get(pid, _guess_tag(pid, cid, diff))

        if tag not in problem_results:
            problem_results[tag] = {}
        if pid not in problem_results[tag]:
            problem_results[tag][pid] = False
        if s.get("result") == "AC":
            problem_results[tag][pid] = True

    result = []
    for tag, pids in problem_results.items():
        total = len(pids)
        ac = sum(1 for v in pids.values() if v)
        if total >= 3:
            result.append({
                "tag": tag,
                "ac_rate": round(ac / total, 2) if total > 0 else 0,
                "total": total,
                "ac": ac,
            })
    result.sort(key=lambda x: -x["ac_rate"])
    return result[:8]


def build_streak_calendar(
    submissions: list[dict],
    difficulties: dict[str, Any],
) -> tuple[list[dict], int, int]:
    # Group all ACs by JST date (including AHC re-submissions)
    by_date: dict[str, set[str]] = {}
    diff_by_date: dict[str, float] = {}
    for s in submissions:
        if s.get("result") != "AC":
            continue
        d = _epoch_to_jst_date(s.get("epoch_second", 0))
        pid = s.get("problem_id", "")
        by_date.setdefault(d, set()).add(pid)
        diff = difficulties.get(pid, {}).get("difficulty") or 0
        if diff < 0:
            diff = 0
        diff_by_date[d] = max(diff_by_date.get(d, 0), diff)

    today = datetime.now(LOCAL_TZ).date()
    calendar: list[dict] = []
    for i in range(139, -1, -1):  # 140 days ≈ 20 weeks
        d = today - timedelta(days=i)
        ds = d.isoformat()
        calendar.append({
            "date": ds,
            "max_difficulty": round(diff_by_date.get(ds, 0)),
            "ac_count": len(by_date.get(ds, set())),
        })

    # Current streak
    current_streak = 0
    check = today
    if today.isoformat() not in by_date:
        check = today - timedelta(days=1)
    while check.isoformat() in by_date:
        current_streak += 1
        check -= timedelta(days=1)

    # Max streak
    all_dates = sorted(by_date.keys())
    max_streak = 0
    run = 0
    prev = None
    for ds in all_dates:
        d = datetime.strptime(ds, "%Y-%m-%d").date()
        if prev is not None and (d - prev).days == 1:
            run += 1
        else:
            run = 1
        max_streak = max(max_streak, run)
        prev = d

    return calendar, current_streak, max_streak


def build_speed(
    submissions: list[dict],
    ratings: list[dict],
) -> list[dict]:
    """Per-contest lap times (A, B, C, ...) from rated contests only."""
    # Build contest start times from rating history
    contest_starts: dict[str, int] = {}
    contest_names: dict[str, str] = {}
    for r in ratings:
        screen = r.get("ContestScreenName", "")
        cid = screen.split(".")[0] if "." in screen else ""
        end_epoch = r.get("EndTime", 0)
        if isinstance(end_epoch, str):
            try:
                end_epoch = int(
                    datetime.fromisoformat(end_epoch).timestamp()
                )
            except ValueError:
                continue
        # ABC = 100min, ARC = 120min
        duration = 7200 if cid.startswith("arc") else 6000
        if cid:
            contest_starts[cid] = end_epoch - duration
            contest_names[cid] = r.get("ContestName", cid)

    # Group AC submissions by contest
    contest_acs: dict[str, list[dict]] = {}
    for s in submissions:
        if s.get("result") != "AC":
            continue
        cid = s.get("contest_id", "")
        if cid not in contest_starts:
            continue
        contest_acs.setdefault(cid, []).append(s)

    result = []
    for cid in sorted(contest_starts.keys(), key=lambda c: contest_starts[c]):
        start = contest_starts[cid]
        acs = contest_acs.get(cid, [])
        if not acs:
            continue

        # First AC per problem, sorted by AC time
        first_ac: dict[str, int] = {}
        for s in sorted(acs, key=lambda x: x["epoch_second"]):
            pid = s.get("problem_id", "")
            if pid not in first_ac:
                first_ac[pid] = s["epoch_second"]

        # Sort by AC time → lap order
        sorted_acs = sorted(first_ac.items(), key=lambda x: x[1])

        laps = []
        prev_time = start
        for pid, ac_time in sorted_acs:
            cumulative = ac_time - start
            lap = ac_time - prev_time
            if cumulative <= 0 or cumulative > 10800:
                continue
            # Problem label: last part after underscore (a, b, c, ...)
            label = pid.rsplit("_", 1)[-1].upper() if "_" in pid else pid
            laps.append({
                "problem": label,
                "cumulative": cumulative,
                "lap": lap,
            })
            prev_time = ac_time

        if laps:
            name = contest_names.get(cid, cid)
            short = name.replace("AtCoder Beginner Contest ", "ABC ")
            short = short.replace("AtCoder Regular Contest ", "ARC ")
            duration = 7200 if cid.startswith("arc") else 6000
            result.append({
                "contest": short,
                "start_epoch": start,
                "duration_seconds": duration,
                "laps": laps,
            })

    return result[-6:]


def build_rating_log(ratings: list[dict]) -> list[dict]:
    """Transform rating history for the difficulty log chart."""
    result = []
    for r in ratings:
        end_time = r.get("EndTime", 0)
        if isinstance(end_time, str):
            try:
                end_time = int(datetime.fromisoformat(end_time).timestamp())
            except ValueError:
                continue
        result.append({
            "epoch": end_time,
            "old_rating": r.get("OldRating", 0),
            "new_rating": r.get("NewRating", 0),
            "contest": r.get("ContestName", ""),
            "place": r.get("Place", 0),
            "performance": r.get("Performance", 0),
        })
    return result


def build_unreviewed_contests() -> list[dict]:
    """Find contests with .contest_mode flag (not yet reviewed)."""
    contests_dir = Path.home() / "cp" / "contests"
    if not contests_dir.exists():
        return []
    unreviewed = []
    for d in sorted(contests_dir.iterdir()):
        flag = d / ".contest_mode"
        if flag.exists():
            try:
                mtime = flag.stat().st_mtime
                days_ago = (time.time() - mtime) / 86400
                unreviewed.append({
                    "contest": d.name,
                    "days_ago": round(days_ago),
                })
            except OSError:
                pass
    return unreviewed


def build_latest_insight() -> dict | None:
    """Read the most recent insight from ~/cp/insights/."""
    insights_dir = Path.home() / "cp" / "insights"
    if not insights_dir.exists():
        return None
    latest_file = None
    latest_mtime = 0.0
    for f in insights_dir.glob("*.md"):
        mt = f.stat().st_mtime
        if mt > latest_mtime:
            latest_mtime = mt
            latest_file = f
    if not latest_file:
        return None
    try:
        content = latest_file.read_text()
        # Parse last entry: ## RESULT DATE\ntags: [tag]\n\ntext
        entries = content.split("\n## ")
        if len(entries) < 2:
            return None
        last = entries[-1]
        lines = last.strip().split("\n")
        header = lines[0]  # "AC 2026-04-17 14:30"
        parts = header.split(None, 1)
        result = parts[0] if parts else ""
        tag = ""
        text_lines: list[str] = []
        for line in lines[1:]:
            if line.startswith("tags: ["):
                tag = line.replace("tags: [", "").replace("]", "").strip()
            elif line.strip():
                text_lines.append(line.strip())
        text = "\n".join(text_lines[:5])
        pid = latest_file.stem
        return {
            "problem_id": pid,
            "tag": tag,
            "text": text,
            "result": result,
        }
    except (OSError, IndexError):
        return None


def build_warmup_candidates(
    submissions: list[dict],
    difficulties: dict[str, Any],
    problems_list: list[dict],
) -> list[dict]:
    """Find warmup problems: diff >= AC'd 25th percentile, closest first.

    Returns 5 unsolved problems near the user's comfort zone floor.
    """
    ac_map = _ac_problems(submissions)
    ac_set = set(ac_map.keys())

    ac_diffs: list[int] = []
    for pid in ac_set:
        diff = difficulties.get(pid, {}).get("difficulty")
        if diff is not None and diff >= 0:
            ac_diffs.append(round(diff))

    if len(ac_diffs) < 5:
        return []

    ac_diffs.sort()
    idx_25 = len(ac_diffs) // 4
    threshold = ac_diffs[idx_25]

    problems_map = {p["id"]: p for p in problems_list}
    candidates: list[dict] = []
    for pid, info in difficulties.items():
        if pid in ac_set:
            continue
        diff = info.get("difficulty")
        if diff is None or diff < threshold:
            continue
        diff = round(diff)
        cid = problems_map.get(pid, {}).get("contest_id", "")
        if not cid:
            continue
        candidates.append({
            "problem_id": pid,
            "contest_id": cid,
            "difficulty": diff,
            "distance": abs(diff - threshold),
        })

    candidates.sort(key=lambda x: x["distance"])
    return [
        {
            "problem_id": c["problem_id"],
            "contest_id": c["contest_id"],
            "difficulty": c["difficulty"],
        }
        for c in candidates[:5]
    ]


def build_compare(submissions: list[dict]) -> dict:
    """Build month-over-month AC comparison."""
    ac_map = _ac_problems(submissions)
    now = datetime.now(LOCAL_TZ)
    this_month = now.strftime("%Y-%m")
    last_month = (now.replace(day=1) - timedelta(days=1)).strftime("%Y-%m")

    this_count = 0
    last_count = 0
    for pid, s in ac_map.items():
        d = _epoch_to_jst_date(s.get("epoch_second", 0))
        if d.startswith(this_month):
            this_count += 1
        elif d.startswith(last_month):
            last_count += 1

    return {
        "this_month_ac": this_count,
        "last_month_ac": last_count,
    }


def build_skill_graph(
    submissions: list[dict],
    difficulties: dict[str, Any],
    problems_list: list[dict],
    ratings: list[dict],
) -> dict:
    """Build skill tree with progress from benchmark problem ACs.

    Each skill has canonical problems. Progress = how many you've AC'd.
    """
    current_rating = ratings[-1]["NewRating"] if ratings else 0
    ac_map = _ac_problems(submissions)
    ac_set = set(ac_map.keys())

    # Benchmark problems per skill: B問題(入門) + C/D問題(習得証明)
    # Sources: 典型90問, EDPC, ABC, e869120ガイド
    BENCHMARKS: dict[str, list[str]] = {
        # Tier 1 (灰→茶): B1問 + C2問
        "bruteforce": [
            "abc083_b",     # Some Sums (桁和で全探索)
            "abc150_b",     # Count ABC (部分文字列全探索)
            "abc167_c",     # Skill Up (bit全探索入門)
        ],
        "sort": [
            "abc088_b",     # Card Game for Two (降順ソート)
            "abc132_c",     # Divide the Problems (ソート+中央値)
            "abc121_c",     # White Cells (ソート+数え上げ)
        ],
        "greedy": [
            "abc086_b",     # 1+1 (基本条件判定)
            "abc134_c",     # Exception Handling (最大値除外)
            "abc131_d",     # Megalomania (スケジューリング貪欲)
        ],
        "string": [
            "abc122_b",     # ATCoder (部分文字列判定)
            "abc139_c",     # Lower (文字列走査)
            "abc049_c",     # Daydream (文字列マッチング)
        ],
        "mapset": [
            "abc081_b",     # Shift only (基本ループ)
            "abc141_c",     # Attack Survival (カウント)
            "abc155_c",     # Poll (Map頻度カウント)
        ],
        "gcd": [
            "abc109_b",     # Shiritori (基本判定)
            "abc118_c",     # Monsters Battle Royale (全要素GCD)
            "abc148_c",     # Snack (LCM基本)
        ],
        "simulation": [
            "abc152_b",     # Comparing Strings (基本実装)
            "abc124_c",     # Coloring Colorfully (反転シミュレーション)
            "abc160_c",     # Traveling Salesman around Lake (環状距離)
        ],
        # Tier 2 (茶→緑): C/D問題 + 典型問題
        "cumsum": [
            "abc120_c",     # Unification (累積的な数え上げ)
            "abc122_c",     # GeT AC (文字列+累積和)
            "typical90_j",  # #010 Score Sum Queries (累積和基本)
        ],
        "binsearch": [
            "typical90_a",  # #001 Yokan Party (答えで二分探索)
            "abc077_c",     # Snuke Festival (lower_bound)
            "abc174_e",     # Logs (最大値の最小化)
        ],
        "basedp": [
            "abc153_d",     # Caracal vs Monster (再帰/分割)
            "dp_a",         # EDPC Frog 1 (DP入門)
            "dp_d",         # EDPC Knapsack 1 (ナップサック)
        ],
        "bfs": [
            "abc007_3",     # 幅優先探索 (迷路BFS)
            "abc088_d",     # Grid Problem (グリッドBFS)
            "abc138_d",     # Ki (木DFS)
        ],
        "twoptr": [
            "typical90_ah", # #034 There are few types (尺取り)
            "abc130_d",     # Enough Array (和の尺取り)
            "abc172_c",     # Tsundoku (2山の尺取り)
        ],
        "bit": [
            "typical90_b",  # #002 括弧列 (bit全探索)
            "abc128_c",     # Switches (bit全探索)
            "abc147_c",     # HonestOrUnkind2 (bit全探索)
        ],
        "prime": [
            "abc142_c",     # Go to School (順列基本)
            "abc084_d",     # 2017-like Number (篩+累積和)
            "abc172_d",     # Sum of Divisors (約数列挙)
        ],
        "complexity": [
            "abc079_c",     # Train Ticket (計算式探索)
            "typical90_d",  # #004 Cross Sum (前計算で高速化)
            "abc176_d",     # Wizard in Maze (0-1 BFS)
        ],
        "unionfind": [
            "typical90_l",  # #012 Red Painting (UF典型)
            "abc177_d",     # Friends (連結成分最大サイズ)
            "abc157_d",     # Friend Suggestions (サイズ付きUF)
        ],
        "pqueue": [
            "abc141_d",     # Powerful Discount Tickets (ヒープ貪欲)
            "abc137_d",     # Summer Vacation (締切+ヒープ)
            "abc153_d",     # Caracal vs Monster (分割/優先度)
        ],
        # Tier 3 (緑→水): 典型 + 応用問題
        "dijkstra": [
            "typical90_m",  # #013 Passing (2回ダイクストラ)
            "abc176_d",     # Wizard in Maze (0-1 BFS)
            "abc192_e",     # Train (拡張ダイクストラ)
        ],
        "segtree": [
            "typical90_ac", # #029 Long Bricks (遅延セグ木)
            "abc185_f",     # Range Xor Query (BIT)
            "dp_q",         # EDPC Flowers (BIT+DP)
        ],
        "bitdp": [
            "dp_o",         # EDPC Matching (bitDP典型)
            "abc180_e",     # TSP (巡回セールスマン)
            "abc142_e",     # Get Everything (集合被覆)
        ],
        "mst": [
            "abc218_e",     # Destruction (MST+負辺)
            "abc065_d",     # Built? (座標+クラスカル)
        ],
        "compress": [
            "abc036_c",     # 座圧 (座標圧縮)
            "abc213_c",     # Reorder Cards (行列圧縮)
            "typical90_ab", # #028 Cluttered Paper (2次元)
        ],
        "modinv": [
            "abc156_c",     # Rally (分散計算)
            "abc145_d",     # Knight (大きなnCr)
            "typical90_bq", # #069 Colorful Blocks 2 (nCr mod p)
        ],
        "imos": [
            "abc014_c",     # AtColor (1次元imos)
            "abc183_d",     # Water Heater (imos基本)
            "typical90_ab", # #028 Cluttered Paper (2次元imos)
        ],
        # Tier 4 (水色→青)
        "digitdp": [
            "dp_s",         # EDPC Digit Sum (桁DP入門)
            "typical90_bl", # #064 Uplift (桁DP応用)
            "abc154_e",     # Almost Everywhere Zero (桁DP)
        ],
        "treedp": [
            "dp_p",         # EDPC Independent Set (木DP入門)
            "dp_v",         # EDPC Subtree (木DP応用)
            "typical90_z",  # #026 Independent Set on a Tree
        ],
        "lca": [
            "abc014_d",     # 閉路 (LCA基本)
            "abc133_f",     # Colorful Tree (LCA+重み)
            "typical90_bf", # #082 Counting Numbers (ダブリング)
        ],
        "scc": [
            "typical90_bu", # #073 We Need Bothabc (2-SAT/SCC)
            "abc245_f",     # Endless Walk (SCC)
        ],
        "lazysegtree": [
            "abc153_f",     # Silver Fox vs Monster (遅延セグ木)
            "abc174_f",     # Range Set Query (BIT応用)
            "typical90_ac", # #029 Long Bricks (遅延セグ木, T3と共有)
        ],
        "strhash": [
            "abc141_e",     # Who Says a Pun? (ローリングハッシュ)
            "abc284_f",     # ABCBAC (ハッシュ判定)
            "typical90_ao", # #041 Piles in AtCoder Farm (凸包/幾何)
        ],
    }

    # Build nodes: progress = [AC'd benchmarks, total benchmarks]
    TREE = [
        {"id": "base",       "label": "基礎",       "tier": 0, "parent": None},
        {"id": "bruteforce", "label": "全探索",     "tier": 1, "parent": "base"},
        {"id": "sort",       "label": "ソート",     "tier": 1, "parent": "base"},
        {"id": "greedy",     "label": "貪欲法",     "tier": 1, "parent": "base"},
        {"id": "string",     "label": "文字列",     "tier": 1, "parent": "base"},
        {"id": "mapset",     "label": "Map/Set",    "tier": 1, "parent": "base"},
        {"id": "gcd",        "label": "GCD/LCM",    "tier": 1, "parent": "base"},
        {"id": "simulation", "label": "実装力",     "tier": 1, "parent": "base"},
        {"id": "cumsum",     "label": "累積和",     "tier": 2, "parent": "bruteforce"},
        {"id": "binsearch",  "label": "二分探索",   "tier": 2, "parent": "sort"},
        {"id": "basedp",     "label": "基礎DP",     "tier": 2, "parent": "bruteforce"},
        {"id": "bfs",        "label": "BFS/DFS",    "tier": 2, "parent": "bruteforce"},
        {"id": "twoptr",     "label": "尺取り法",   "tier": 2, "parent": "sort"},
        {"id": "bit",        "label": "ビット演算", "tier": 2, "parent": "bruteforce"},
        {"id": "prime",      "label": "素数/約数",  "tier": 2, "parent": "gcd"},
        {"id": "complexity", "label": "計算量",     "tier": 2, "parent": "sort"},
        {"id": "unionfind",  "label": "Union-Find", "tier": 2, "parent": "bfs"},
        {"id": "pqueue",     "label": "優先度Queue","tier": 2, "parent": "sort"},
        {"id": "dijkstra",   "label": "最短路",     "tier": 3, "parent": "bfs"},
        {"id": "segtree",    "label": "セグ木/BIT", "tier": 3, "parent": "cumsum"},
        {"id": "bitdp",      "label": "bitDP",      "tier": 3, "parent": "bit"},
        {"id": "mst",        "label": "MST",        "tier": 3, "parent": "bfs"},
        {"id": "compress",   "label": "座標圧縮",   "tier": 3, "parent": "binsearch"},
        {"id": "modinv",     "label": "mod逆元",    "tier": 3, "parent": "prime"},
        {"id": "imos",       "label": "imos法",      "tier": 3, "parent": "cumsum"},
        {"id": "digitdp",   "label": "桁DP",       "tier": 4, "parent": "basedp"},
        {"id": "treedp",    "label": "木DP",       "tier": 4, "parent": "basedp"},
        {"id": "lca",       "label": "LCA",        "tier": 4, "parent": "dijkstra"},
        {"id": "scc",       "label": "強連結成分",  "tier": 4, "parent": "dijkstra"},
        {"id": "lazysegtree","label": "遅延セグ木", "tier": 4, "parent": "segtree"},
        {"id": "strhash",   "label": "文字列Hash", "tier": 4, "parent": "compress"},
    ]

    # 自分の色 + 2ティアまで表示
    # Rating→tier: 0-399=T1, 400-799=T2, 800-1199=T3, 1200+=T4
    rating_tier = 1
    if current_rating >= 1200:
        rating_tier = 4
    elif current_rating >= 800:
        rating_tier = 3
    elif current_rating >= 400:
        rating_tier = 2
    max_tier = min(rating_tier + 2, 4)

    # Load SRS data for mastery status
    srs_data: dict = {}
    srs_path = Path.home() / "cp" / "srs.json"
    if srs_path.exists():
        try:
            srs_data = json.loads(srs_path.read_text())
        except (json.JSONDecodeError, OSError):
            pass

    nodes = []
    for n in TREE:
        if n["tier"] > max_tier:
            continue
        sid = n["id"]
        if sid == "base":
            progress = [len(ac_map), len(ac_map)] if ac_map else [0, 1]
            mastery = [0, 0, 0]  # [未着手, 接触済, 定着]
        else:
            benchmarks = BENCHMARKS.get(sid, [])
            untouched = 0
            touched = 0
            mastered = 0
            for p in benchmarks:
                if p not in ac_set:
                    untouched += 1
                elif p not in srs_data or srs_data.get(p, {}).get("graduated", False):
                    # AC'd and either not in SRS (solved without help)
                    # or SRS graduated → mastered
                    mastered += 1
                else:
                    # In SRS but not yet graduated → touched
                    touched += 1
            progress = [touched + mastered, len(benchmarks)]
            mastery = [untouched, touched, mastered]
        node = {
            "id": sid, "label": n["label"], "tier": n["tier"],
            "progress": progress,
            "mastery": mastery,  # [未着手, 接触済, 定着]
        }
        if n["parent"]:
            node["parent"] = n["parent"]
        if sid in BENCHMARKS:
            node["benchmarks"] = [
                {
                    "id": p,
                    "ac": p in ac_set,
                    "graduated": (
                        p in ac_set and p not in srs_data
                    ) or srs_data.get(p, {}).get(
                        "graduated", False
                    ),
                }
                for p in BENCHMARKS[sid]
            ]
        nodes.append(node)

    return {
        "rating": current_rating,
        "nodes": nodes,
        "tiers": [t for t in [
            {"tier": 0, "label": "基礎", "color": "#808080"},
            {"tier": 1, "label": "灰→茶", "color": "#804000"},
            {"tier": 2, "label": "茶→緑", "color": "#008000"},
            {"tier": 3, "label": "緑→水", "color": "#00C0C0"},
            {"tier": 4, "label": "水→青", "color": "#0000FF"},
        ] if t["tier"] <= max_tier],
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch AtCoder stats")
    parser.add_argument("--user", required=True)
    parser.add_argument(
        "--output",
        default=str(Path.home() / ".cache" / "cp-dashboard" / "stats.json"),
    )
    parser.add_argument(
        "--cache-dir",
        default=str(Path.home() / ".cache" / "cp-dashboard"),
    )
    args = parser.parse_args()

    cfg = Config(
        username=args.user,
        cache_dir=Path(args.cache_dir),
        output_path=Path(args.output),
    )
    cfg.cache_dir.mkdir(parents=True, exist_ok=True)

    print(f"[fetch_stats] Fetching data for {cfg.username}...", file=sys.stderr)

    # --- Fetch all data ---
    ratings = fetch_rating_history(cfg)
    submissions = fetch_submissions_kenkoooo(cfg)
    difficulties = fetch_difficulties_kenkoooo(cfg)
    problems_list = fetch_problems_kenkoooo(cfg)
    upcoming = fetch_upcoming_contests(cfg)
    tag_overrides = _load_tag_overrides()

    has_submissions = len(submissions) > 0

    print(
        f"[fetch_stats] {len(submissions)} submissions, "
        f"{len(ratings)} rated contests, "
        f"{len(upcoming)} upcoming contests",
        file=sys.stderr,
    )

    # --- Build sections ---
    calendar, streak_days, max_streak = (
        build_streak_calendar(submissions, difficulties)
        if has_submissions
        else ([], 0, 0)
    )

    stats: dict[str, Any] = {
        "generated_at": datetime.now(LOCAL_TZ).isoformat(),
        "user": cfg.username,
        "has_submissions": has_submissions,
        "hud": build_hud(submissions, ratings, streak_days, max_streak),
        "player_status": build_player_status(
            submissions, ratings, difficulties, streak_days, max_streak
        ),
        "difficulty_log": (
            build_difficulty_log(submissions, difficulties, ratings)
            if has_submissions
            else {"points": [], "seven_day_avg": [], "current_rating": 0}
        ),
        "streak_calendar": calendar,
        "contests": upcoming,
        "rating_history": build_rating_log(ratings),
        "skill_graph": build_skill_graph(
            submissions, difficulties, problems_list, ratings
        ),
        "daily_volume": (
            build_daily_volume(submissions, difficulties)
            if has_submissions
            else {"days": []}
        ),
    }

    # Atomic write
    tmp = cfg.output_path.with_suffix(".tmp")
    cfg.output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(json.dumps(stats, ensure_ascii=False, indent=2))
    os.replace(str(tmp), str(cfg.output_path))

    print(f"[fetch_stats] Written to {cfg.output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
