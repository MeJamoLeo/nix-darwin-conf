#!/usr/bin/env python3
"""Fetch AtCoder NoviSteps progress for a user via authenticated scraping.

Requires a Lucia `auth_session` cookie obtained from the browser after login.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

try:
    LOCAL_TZ = datetime.now().astimezone().tzinfo
except Exception:
    LOCAL_TZ = timezone.utc

BASE = "https://atcoder-novisteps.vercel.app"
DEFAULT_COOKIE_PATH = Path.home() / "tmp" / "cp-navisteps" / "auth_session"
DEFAULT_OUTPUT = Path.home() / ".cache" / "cp-dashboard" / "novisteps.json"
REQUEST_DELAY = 1.0

# Workbook list: title appears in a tight context just before the urlSlug.
# This regex avoids the description field (which may contain quotes) by
# anchoring on the run of boolean flags between title and urlSlug.
WORKBOOK_RE = re.compile(
    r'title:"([^"]+)"'
    r'(?:[^{}]*?)'
    r'workBookType:"SOLUTION",urlSlug:"([^"]+)"'
)

TASK_RE = re.compile(
    r'task_id:"([^"]+)"[^{}]*?grade:"([^"]+)"[^{}]*?'
    r'status_name:"([^"]+)"[^{}]*?is_ac:(true|false)[^{}]*?'
    r'updated_at:new Date\((\d+)\)'
)

USER_RE = re.compile(r'user:\{id:"[^"]+",name:"([^"]+)"')


class CookieExpired(Exception):
    pass


NOVISTEPS_KEYCHAIN_SERVICE = "novisteps-auth-session"


def novisteps_session() -> str:
    """auth_session cookie を env（テスト用）or login Keychain から取る。
    平文ファイルは廃止（2026-07 方針）。cookie は Anjin の Chrome から一度だけ
    ローカル復号して格納済み（-T /usr/bin/security で無人 launchd も読める）。
    失効したら再復号（scripts の cp-novisteps-login 等）で入れ直す。"""
    env = os.environ.get("CP_NOVISTEPS_SESSION")
    if env:
        return env
    try:
        r = subprocess.run(
            ["/usr/bin/security", "find-generic-password",
             "-s", NOVISTEPS_KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise SystemExit(f"Keychain 読み出し失敗: {e}")
    tok = r.stdout.strip()
    if r.returncode != 0 or not tok:
        raise SystemExit(
            f"NoviSteps cookie が Keychain に無い（service={NOVISTEPS_KEYCHAIN_SERVICE}）。"
            "Anjin にログインしてから cookie を復号・格納してください。")
    return tok


def load_cookie(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"cookie file not found: {path}")
    val = path.read_text().strip()
    if not val:
        raise SystemExit(f"cookie file is empty: {path}")
    return val


def fetch(url: str, cookie: str, retries: int = 1) -> str:
    last_err: Exception | None = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (X11; Linux x86_64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/json,*/*",
                "Accept-Encoding": "gzip",
                "Cookie": f"auth_session={cookie}",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                final_url = resp.geturl()
                if "/login" in final_url:
                    raise CookieExpired(
                        f"auth_session expired or invalid (redirected to {final_url})"
                    )
                data = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    data = gzip.decompress(data)
                return data.decode("utf-8", errors="replace")
        except CookieExpired:
            raise
        except (urllib.error.URLError, OSError) as e:
            last_err = e
            if attempt < retries:
                time.sleep(3)
                continue
    raise SystemExit(f"fetch failed: {url}: {last_err}")


def parse_workbook_index(html: str) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for title, slug in WORKBOOK_RE.findall(html):
        if slug in seen:
            continue
        seen.add(slug)
        out.append({"slug": slug, "title": title})
    return out


def parse_workbook_tasks(html: str) -> list[dict]:
    return [
        {
            "task_id": tid,
            "grade": grade,
            "status": status,
            "is_ac": is_ac == "true",
            "updated_at": int(ts),
        }
        for tid, grade, status, is_ac, ts in TASK_RE.findall(html)
    ]


def parse_username(html: str) -> str:
    m = USER_RE.search(html)
    return m.group(1) if m else ""


def write_output(output_path: Path, payload: dict) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = output_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    os.replace(str(tmp), str(output_path))


def fetch_index(cookie: str) -> tuple[str, list[dict]]:
    print(f"[novisteps] fetching workbook index...", file=sys.stderr)
    index_html = fetch(f"{BASE}/workbooks?tab=solution", cookie)
    return parse_username(index_html), parse_workbook_index(index_html)


def fetch_workbook(slug: str, cookie: str) -> list[dict]:
    html = fetch(f"{BASE}/workbooks/{slug}", cookie)
    return parse_workbook_tasks(html)


def handle_cookie_expired(output_path: Path, exc: CookieExpired) -> None:
    """Mark JSON as cookie_expired so the dashboard can show a banner."""
    print(f"[novisteps] COOKIE_EXPIRED: {exc}\n"
          f"  → Anjin で NoviSteps に再ログイン後、cookie を復号して Keychain "
          f"(service={NOVISTEPS_KEYCHAIN_SERVICE}) に入れ直す", file=sys.stderr)
    existing: dict = {}
    if output_path.exists():
        try:
            existing = json.loads(output_path.read_text())
        except (json.JSONDecodeError, OSError):
            existing = {}
    existing["cookie_expired"] = True
    write_output(output_path, existing)
    sys.exit(2)


def run_one(args, cookie: str) -> None:
    output_path = Path(args.output)
    existing: dict = {}
    if output_path.exists():
        try:
            existing = json.loads(output_path.read_text())
        except (json.JSONDecodeError, OSError):
            existing = {}
    workbooks_data: dict = existing.get("workbooks", {}) or {}

    try:
        username, workbooks = fetch_index(cookie)
    except CookieExpired as e:
        handle_cookie_expired(output_path, e)
    print(
        f"[novisteps] user={username or '?'}, "
        f"{len(workbooks)} SOLUTION workbooks",
        file=sys.stderr,
    )

    known_slugs = {wb["slug"] for wb in workbooks}
    for stale in list(workbooks_data.keys()):
        if stale not in known_slugs:
            workbooks_data.pop(stale, None)

    def sort_key(wb: dict) -> tuple[int, str]:
        slug = wb["slug"]
        entry = workbooks_data.get(slug)
        if not entry or "fetched_at" not in entry:
            return (0, slug)
        return (1, entry["fetched_at"])

    workbooks.sort(key=sort_key)
    target = workbooks[0]
    slug = target["slug"]
    print(f"[novisteps] picking {slug}", file=sys.stderr)

    try:
        tasks = fetch_workbook(slug, cookie)
    except CookieExpired as e:
        handle_cookie_expired(output_path, e)
    workbooks_data[slug] = {
        "title": target["title"],
        "tasks": tasks,
        "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
    }

    out = {
        "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
        "user": username,
        "cookie_expired": False,
        "workbooks": workbooks_data,
    }
    write_output(output_path, out)

    total_tasks = sum(len(w.get("tasks", [])) for w in workbooks_data.values())
    print(
        f"[novisteps] updated {slug} "
        f"({len(tasks)} tasks); total {len(workbooks_data)} workbooks, "
        f"{total_tasks} tasks",
        file=sys.stderr,
    )


def run_task(args, cookie: str) -> None:
    output_path = Path(args.output)
    existing: dict = {}
    if output_path.exists():
        try:
            existing = json.loads(output_path.read_text())
        except (json.JSONDecodeError, OSError):
            existing = {}
    workbooks_data: dict = existing.get("workbooks", {}) or {}

    if not workbooks_data:
        print("[novisteps] no local mapping; falling back to full fetch", file=sys.stderr)
        run_all(args, cookie)
        return

    targets = set(args.task)
    slugs = [
        slug for slug, wb in workbooks_data.items()
        if any(t.get("task_id") in targets for t in wb.get("tasks", []))
    ]

    if not slugs:
        print(
            f"[novisteps] {sorted(targets)} not in any tracked workbook; skip",
            file=sys.stderr,
        )
        return

    print(f"[novisteps] refreshing {len(slugs)} workbook(s): {slugs}", file=sys.stderr)

    for i, slug in enumerate(slugs, 1):
        if i > 1:
            time.sleep(args.delay)
        try:
            tasks = fetch_workbook(slug, cookie)
        except CookieExpired as e:
            handle_cookie_expired(output_path, e)
        workbooks_data[slug] = {
            "title": workbooks_data[slug].get("title", ""),
            "tasks": tasks,
            "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
        }

    out = {
        "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
        "user": existing.get("user", ""),
        "cookie_expired": False,
        "workbooks": workbooks_data,
    }
    write_output(output_path, out)


def run_all(args, cookie: str) -> None:
    output_path = Path(args.output)
    try:
        username, workbooks = fetch_index(cookie)
    except CookieExpired as e:
        handle_cookie_expired(output_path, e)
    print(
        f"[novisteps] user={username or '?'}, "
        f"{len(workbooks)} SOLUTION workbooks",
        file=sys.stderr,
    )

    result: dict = {}
    now_iso = datetime.now(LOCAL_TZ).isoformat()
    for i, wb in enumerate(workbooks, 1):
        slug = wb["slug"]
        print(f"[novisteps] ({i}/{len(workbooks)}) {slug}", file=sys.stderr)
        try:
            tasks = fetch_workbook(slug, cookie)
        except CookieExpired as e:
            handle_cookie_expired(output_path, e)
        result[slug] = {
            "title": wb["title"],
            "tasks": tasks,
            "fetched_at": now_iso,
        }
        if i < len(workbooks):
            time.sleep(args.delay)

    out = {
        "fetched_at": datetime.now(LOCAL_TZ).isoformat(),
        "user": username,
        "cookie_expired": False,
        "workbooks": result,
    }
    write_output(output_path, out)

    total_tasks = sum(len(w["tasks"]) for w in result.values())
    print(
        f"[novisteps] wrote {args.output} "
        f"({len(result)} workbooks, {total_tasks} tasks)",
        file=sys.stderr,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch NoviSteps progress")
    parser.add_argument(
        "--cookie", default=None,
        help="（任意）auth_session を含むファイルパス。未指定なら Keychain から読む",
    )
    parser.add_argument(
        "--output", default=str(DEFAULT_OUTPUT),
        help="output JSON path",
    )
    parser.add_argument(
        "--delay", type=float, default=REQUEST_DELAY,
        help="seconds between workbook fetches (only used in full mode)",
    )
    parser.add_argument(
        "--one", action="store_true",
        help="fetch only the least-recently-updated workbook (plus index)",
    )
    parser.add_argument(
        "--task", action="append", default=None, metavar="TASK_ID",
        help="refresh only workbooks containing this task_id "
             "(repeatable). Falls back to full fetch when the local "
             "mapping is empty.",
    )
    args = parser.parse_args()

    # cookie: --cookie ファイル指定があればそれ、無ければ Keychain（既定）
    cookie = load_cookie(Path(args.cookie)) if args.cookie else novisteps_session()
    if args.task:
        run_task(args, cookie)
    elif args.one:
        run_one(args, cookie)
    else:
        run_all(args, cookie)


if __name__ == "__main__":
    main()
