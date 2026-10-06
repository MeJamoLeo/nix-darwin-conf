"""llm — `claude -p` を headless で叩く共通部（blocks の分類・gcal のカレンダー取得）。

呼び方は claude-obsidian の bin/mail-check.sh と同じ（`claude -p --model haiku --effort low`）。launchd の
最小 PATH でも動くよう、claude は env TODO_BOARD_CLAUDE（home.nix が渡す）→ PATH の順で探す。
認証は macOS keychain 経由なので LaunchAgent（GUI セッション）で動く。
"""
import os
import shutil
import subprocess
import tempfile


class LLMError(Exception):
    pass


def run_claude(prompt, allowed_tools=(), timeout=240):
    """プロンプトを stdin で渡し、stdout を返す。失敗は LLMError。

    ・cwd は中立ディレクトリ（プロジェクトの CLAUDE.md／hook を拾わせない）。
    ・--no-session-persistence で呼び出し自体を transcript に残さない（record-blocks にも映らない）。
    ・allowed_tools があれば --allowedTools に渡す（無ければツールは使わせない前提の純分類）。
    """
    exe = os.environ.get("TODO_BOARD_CLAUDE") or shutil.which("claude")
    if not exe:
        raise LLMError("claude not found in PATH")
    cmd = [exe, "-p", "--model", "haiku", "--effort", "low", "--no-session-persistence"]
    if allowed_tools:
        cmd += ["--allowedTools", ",".join(allowed_tools)]
    try:
        r = subprocess.run(cmd, input=prompt, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                           timeout=timeout, cwd=tempfile.gettempdir())
    except Exception as e:
        raise LLMError(f"claude failed: {type(e).__name__}")
    if r.returncode != 0:
        raise LLMError(f"claude exit {r.returncode}: {r.stderr.strip()[:120]}")
    return r.stdout
