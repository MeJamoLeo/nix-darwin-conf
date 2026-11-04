"""Canvas（TXST）API の読み取り専用クライアント。標準ライブラリのみ。

元は modules/apps/claude/skills/course/canvas.py。task_loop は別経路でデプロイされる
（~/.local/lib/task-loop）ので、skill 側を import せず最小限をコピーしてある。
★ トークンは print / log しない（例外メッセージにも入れない）。
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import urllib.error
import urllib.request

CANVAS_BASE = "https://canvas.txstate.edu/api/v1"


class CanvasError(RuntimeError):
    pass


def _run(args: list[str], timeout: int) -> tuple[int, str]:
    # stdin を閉じるのは、Keychain / rbw に対話プロンプトを出させないため。
    try:
        r = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def get_token() -> str:
    """Keychain → だめなら rbw（解錠済みのときだけ。launchd からは解錠を頼めないため）。"""
    rc, tok = _run(["/usr/bin/security", "find-generic-password", "-s", "canvas-txst-token", "-w"], 10)
    if rc == 0 and tok:
        return tok
    rb = shutil.which("rbw")
    if rb and _run([rb, "unlocked"], 10)[0] == 0:
        rc, tok = _run([rb, "get", "canvas-open-api"], 15)
        if rc == 0 and tok:
            return tok
        raise CanvasError("Canvas トークンが取れない（Keychain に無く、rbw の取得も失敗）")
    raise CanvasError("Canvas トークンが取れない（Keychain に無く、rbw はロック中）")


def _next_link(header: str | None) -> str | None:
    """Link ヘッダから rel="next" の URL を取り出す。"""
    for part in (header or "").split(","):
        m = re.match(r'\s*<([^>]+)>\s*;\s*rel="?next"?', part)
        if m:
            return m.group(1)
    return None


def get_all(path: str, token: str | None = None) -> list:
    """GET して、Link ヘッダの next を辿って全ページを結合する（per_page=100 で足りない場合に備える）。"""
    tok = token or get_token()
    url: str | None = CANVAS_BASE + path
    out: list = []
    pages = 0
    while url:
        pages += 1
        if pages > 50:  # 無限ループの保険
            raise CanvasError("Canvas ページ送りが50ページを超えた")
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}", "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = json.loads(r.read().decode("utf-8"))
                url = _next_link(r.headers.get("Link"))
        except urllib.error.HTTPError as e:
            raise CanvasError(f"Canvas HTTP {e.code}: {path}") from None
        except Exception as e:  # URL にトークンは入らないが、例外文面は型名だけにしておく
            raise CanvasError(f"Canvas 取得失敗 ({type(e).__name__}): {path}") from None
        if isinstance(body, list):
            out.extend(body)
        else:
            out.append(body)
    return out


def assignments_with_submission() -> dict[str, dict]:
    """受講中の全コースの課題を {assignmentId(str): {name, course, submission}} で返す。"""
    tok = get_token()
    result: dict[str, dict] = {}
    for c in get_all("/courses?enrollment_state=active&per_page=50", tok):
        cid = c.get("id")
        if cid is None:
            continue
        label = c.get("course_code") or c.get("name") or str(cid)
        for a in get_all(f"/courses/{cid}/assignments?include[]=submission&per_page=100", tok):
            result[str(a["id"])] = {
                "name": a.get("name", ""),
                "course": label,
                "submission": a.get("submission"),
                "due_at": a.get("due_at"),
            }
    return result
