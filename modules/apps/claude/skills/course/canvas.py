"""Canvas（TXST）API の読み取り専用クライアント。course スキルが使う。

元は todo-board の todo_board/canvas.py の一部。todo-board を廃止した（2026-11-03）ので、
course が使っていた http_get_json とトークン取得だけをここに移した。標準ライブラリのみ。

使い方:
    python3 -c "
    import sys, os; sys.path.insert(0, os.path.expanduser('~/.claude/skills/course'))
    import canvas
    print(canvas.http_get_json('/courses?enrollment_state=active&per_page=50'))
    "
"""
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request

CANVAS_BASE = "https://canvas.txstate.edu/api/v1"


class CanvasError(Exception):
    pass


def _run_out(args, timeout):
    """子プロセスの stdout（失敗なら ""）。stdin は閉じて、対話プロンプトを出させない。"""
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
    """Keychain → だめなら rbw（解錠済みのときだけ）。★ トークンは print/log しない。"""
    tok = _run_out(["/usr/bin/security", "find-generic-password", "-s", "canvas-txst-token", "-w"], 10)
    if tok:
        return tok
    rb = shutil.which("rbw")
    if rb and _run_rc([rb, "unlocked"], 10) == 0:
        tok = _run_out([rb, "get", "canvas-open-api"], 15)
        if tok:
            return tok
        raise CanvasError("no Canvas token (Keychain missing, rbw lookup failed)")
    raise CanvasError("no Canvas token (Keychain missing, rbw locked)")


def http_get_json(path):
    """Canvas API の GET。path は /courses/... のように API ルートからの相対。"""
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
