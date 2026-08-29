#!/usr/bin/env python3
"""Fetch AtCoder NoviSteps progress for a user via authenticated scraping.

`auth_session` cookie は Keychain (service=novisteps-auth-session) から読む。
失効を検知したら Keychain の username/password (service=novisteps-password) で
自動ログインして cookie を取り直す（自己修復）。人間の手番は資格情報を一度
入れるときだけで、以後は発生しない。
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
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

try:
    LOCAL_TZ = datetime.now().astimezone().tzinfo
except Exception:
    LOCAL_TZ = timezone.utc

BASE = "https://atcoder-novisteps.vercel.app"
LOGIN_URL = f"{BASE}/login"
DEFAULT_COOKIE_PATH = Path.home() / "tmp" / "cp-navisteps" / "auth_session"
DEFAULT_OUTPUT = Path.home() / ".cache" / "cp-dashboard" / "novisteps.json"
REQUEST_DELAY = 1.0

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

SET_COOKIE_RE = re.compile(r"auth_session=([^;]+)")

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


class LoginFailed(Exception):
    pass


NOVISTEPS_KEYCHAIN_SERVICE = "novisteps-auth-session"
NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE = "novisteps-password"


def _keychain(service: str, *extra: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", service, *extra],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise SystemExit(f"Keychain 読み出し失敗: {e}")


def _keychain_password(service: str) -> str:
    r = _keychain(service, "-w")
    return r.stdout.strip() if r.returncode == 0 else ""


def _keychain_account(service: str) -> str:
    """item の acct 欄（＝NoviSteps のユーザ名）を読む。-w と違い値は出さない。"""
    r = _keychain(service)
    if r.returncode != 0:
        return ""
    m = re.search(r'"acct"<blob>="([^"]*)"', r.stdout)
    return m.group(1) if m else ""


def novisteps_session() -> str:
    """auth_session cookie を env（テスト用）or login Keychain から取る。
    平文ファイルは廃止（2026-07 方針）。無い／失効しても自動ログインが拾うので、
    ここでは空文字を返すに留める（呼び出し側が Session.relogin() を試みる）。"""
    env = os.environ.get("CP_NOVISTEPS_SESSION")
    if env:
        return env
    return _keychain_password(NOVISTEPS_KEYCHAIN_SERVICE)


def novisteps_credentials() -> tuple[str, str] | None:
    """自動ログイン用の username/password。ユーザ名は acct 欄に置く規約：

        security add-generic-password -U -s novisteps-password \
            -a '<NoviSteps のユーザ名>' -T /usr/bin/security -w '<パスワード>'
    """
    env_user = os.environ.get("CP_NOVISTEPS_USER")
    env_pass = os.environ.get("CP_NOVISTEPS_PASSWORD")
    if env_user and env_pass:
        return env_user, env_pass
    username = _keychain_account(NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE)
    password = _keychain_password(NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE)
    return (username, password) if username and password else None


def store_session(cookie: str) -> None:
    # Why not stdin: `security add-generic-password` は -w の値を argv でしか
    # 受けない（tty プロンプトは無人 launchd で使えない）。tools/scripts/cp-login
    # と同じ既知のトレードオフ。
    subprocess.run(
        ["/usr/bin/security", "add-generic-password", "-U",
         "-s", NOVISTEPS_KEYCHAIN_SERVICE,
         "-a", os.environ.get("USER", ""),
         "-T", "/usr/bin/security", "-w", cookie],
        capture_output=True, text=True, timeout=10)


def notify(title: str, message: str) -> None:
    """通知センターに出す。盤面の `novisteps <age> cookie ✕` は既にあるが、
    2026-08-16 の事故では出ていても 9 時間気づかなかった。"""
    script = (f"display notification {json.dumps(message)} "
              f"with title {json.dumps(title)}")
    try:
        subprocess.run(["/usr/bin/osascript", "-e", script],
                       capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """303 を追わない。追うと Set-Cookie を載せた応答が捨てられる。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def login(username: str, password: str) -> str:
    """POST /login して新しい auth_session を得る。

    NoviSteps 側は SvelteKit の default form action
    （src/routes/(auth)/login/+page.server.ts、フィールドは username/password）。
    svelte.config.js に csrf の上書きが無い＝既定の checkOrigin が有効なので、
    Origin ヘッダが origin と一致しないと 403 で弾かれる。
    """
    body = urllib.parse.urlencode(
        {"username": username, "password": password}).encode()
    req = urllib.request.Request(
        LOGIN_URL,
        data=body,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded",
            "Origin": BASE,
            "Referer": LOGIN_URL,
            "Accept": "text/html,*/*",
        },
    )
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        resp = opener.open(req, timeout=30)
        status, headers = resp.status, resp.headers
        resp.close()
    except urllib.error.HTTPError as e:
        # リダイレクトを追わないので、成功時の 303 もここに落ちてくる
        status, headers = e.code, e.headers
        e.close()
    except (urllib.error.URLError, OSError) as e:
        raise LoginFailed(f"POST {LOGIN_URL}: {e}") from e

    if status not in (301, 302, 303, 307, 308):
        raise LoginFailed(
            f"HTTP {status}（ユーザ名/パスワード違い、または CSRF 拒否）")

    for value in headers.get_all("Set-Cookie") or []:
        m = SET_COOKIE_RE.match(value.strip())
        if m:
            return m.group(1)
    raise LoginFailed("ログインは通ったが Set-Cookie に auth_session が無い")


class Session:
    """auth_session を保持し、失効時に一度だけ自動で取り直す。

    1 プロセス 1 回に制限しているのは、資格情報が古いときに /login を
    叩き続けないため（非公式サービスへの負荷を増やさない方針）。
    """

    def __init__(self, cookie: str, auto_login: bool = True) -> None:
        self.cookie = cookie
        self.auto_login = auto_login
        self.relogin_attempted = False

    def relogin(self) -> bool:
        if not self.auto_login or self.relogin_attempted:
            return False
        self.relogin_attempted = True
        creds = novisteps_credentials()
        if not creds:
            print("[novisteps] 自動ログイン不可: Keychain に "
                  f"service={NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE} が無い",
                  file=sys.stderr)
            return False
        username, password = creds
        print(f"[novisteps] auth_session 失効 → 自動ログイン中 (user={username})",
              file=sys.stderr)
        try:
            self.cookie = login(username, password)
        except LoginFailed as e:
            print(f"[novisteps] 自動ログイン失敗: {e}", file=sys.stderr)
            return False
        # Why not: env で資格情報を渡すのは切り分け・guest での経路確認用なので、
        # そのセッションで本番の Keychain item を上書きしない。
        if os.environ.get("CP_NOVISTEPS_USER"):
            print("[novisteps] 自動ログイン成功（env 経路のため Keychain は更新しない）",
                  file=sys.stderr)
            return True
        store_session(self.cookie)
        print("[novisteps] 自動ログイン成功 — Keychain の auth_session を更新",
              file=sys.stderr)
        return True


def load_cookie(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"cookie file not found: {path}")
    val = path.read_text().strip()
    if not val:
        raise SystemExit(f"cookie file is empty: {path}")
    return val


def _fetch_once(url: str, cookie: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/json,*/*",
            "Accept-Encoding": "gzip",
            "Cookie": f"auth_session={cookie}",
        },
    )
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


def fetch(url: str, session: Session, retries: int = 1) -> str:
    last_err: Exception | None = None
    for attempt in range(retries + 1):
        try:
            return _fetch_once(url, session.cookie)
        except CookieExpired:
            # 自己修復: 再ログインできたら同じ URL を新 cookie で引き直す。
            # 2 度目の失効はそのまま投げて handle_cookie_expired に任せる。
            if not session.relogin():
                raise
            return _fetch_once(url, session.cookie)
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


def fetch_index(session: Session) -> tuple[str, list[dict]]:
    print(f"[novisteps] fetching workbook index...", file=sys.stderr)
    index_html = fetch(f"{BASE}/workbooks?tab=solution", session)
    return parse_username(index_html), parse_workbook_index(index_html)


def fetch_workbook(slug: str, session: Session) -> list[dict]:
    html = fetch(f"{BASE}/workbooks/{slug}", session)
    return parse_workbook_tasks(html)


def handle_cookie_expired(output_path: Path, exc: CookieExpired) -> None:
    """Mark JSON as cookie_expired so the dashboard can show a banner.

    ここに来る＝自動ログインも失敗した（＝資格情報が古いか、サイト側が変わった）。
    盤面の表示だけでは気づかない実績があるので通知も出す。
    """
    print(f"[novisteps] COOKIE_EXPIRED: {exc}\n"
          f"  → 自動ログインも失敗。Keychain の "
          f"service={NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE} "
          f"（acct=ユーザ名 / パスワード）を確認する", file=sys.stderr)
    notify("NoviSteps 取得が停止",
           "auth_session 失効かつ自動ログイン失敗。Keychain の "
           "novisteps-password を確認して。")
    existing: dict = {}
    if output_path.exists():
        try:
            existing = json.loads(output_path.read_text())
        except (json.JSONDecodeError, OSError):
            existing = {}
    existing["cookie_expired"] = True
    write_output(output_path, existing)
    sys.exit(2)


def run_one(args, session: Session) -> None:
    output_path = Path(args.output)
    existing: dict = {}
    if output_path.exists():
        try:
            existing = json.loads(output_path.read_text())
        except (json.JSONDecodeError, OSError):
            existing = {}
    workbooks_data: dict = existing.get("workbooks", {}) or {}

    try:
        username, workbooks = fetch_index(session)
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
        tasks = fetch_workbook(slug, session)
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


def run_task(args, session: Session) -> None:
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
        run_all(args, session)
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
            tasks = fetch_workbook(slug, session)
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


def run_all(args, session: Session) -> None:
    output_path = Path(args.output)
    try:
        username, workbooks = fetch_index(session)
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
            tasks = fetch_workbook(slug, session)
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
    parser.add_argument(
        "--no-auto-login", action="store_true",
        help="失効しても自動ログインしない（切り分け用）",
    )
    args = parser.parse_args()

    # cookie: --cookie ファイル指定があればそれ、無ければ Keychain（既定）
    cookie = load_cookie(Path(args.cookie)) if args.cookie else novisteps_session()
    session = Session(cookie, auto_login=not args.no_auto_login)
    # cookie が最初から無い場合もログインで取れる（初回セットアップ・15日以上のオフ）
    if not session.cookie and not session.relogin():
        raise SystemExit(
            "auth_session が Keychain に無く、自動ログインもできない。\n"
            f"  cookie:   service={NOVISTEPS_KEYCHAIN_SERVICE}\n"
            f"  password: service={NOVISTEPS_PASSWORD_KEYCHAIN_SERVICE}"
            "（acct 欄に NoviSteps のユーザ名）")

    if args.task:
        run_task(args, session)
    elif args.one:
        run_one(args, session)
    else:
        run_all(args, session)


if __name__ == "__main__":
    main()
