"""orca CLI の薄いラッパー。Linear も Orca も、この CLI 経由でだけ触る。

判断はしない（呼んで JSON を返すだけ）。判断は各ジョブのコードが持つ。
"""

from __future__ import annotations

import json
import os
import subprocess

ORCA = os.environ.get("TASK_LOOP_ORCA", "orca")


class OrcaError(RuntimeError):
    pass


def run(*args: str, timeout: int = 120) -> dict:
    """`orca <args> --json` を実行し、result を返す。失敗は OrcaError。"""
    cmd = [ORCA, *args, "--json"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise OrcaError(f"{' '.join(args[:3])}: {e}") from e
    try:
        data = json.loads(p.stdout)
    except json.JSONDecodeError as e:
        msg = (p.stderr or p.stdout).strip().splitlines()[-1:] or ["(出力なし)"]
        raise OrcaError(f"{' '.join(args[:3])}: {msg[0]}") from e
    if not data.get("ok", False):
        raise OrcaError(f"{' '.join(args[:3])}: {json.dumps(data.get('error'), ensure_ascii=False)}")
    return data["result"]


# --- Orca worktree ---------------------------------------------------------


def worktrees() -> list[dict]:
    return run("worktree", "list")["worktrees"]


def worktree_rm(worktree_id: str) -> dict:
    # --force は付けない：変更の残ったワークスペースは消えないことを前提にする。
    return run("worktree", "rm", "--worktree", f"id:{worktree_id}")


# --- Linear ----------------------------------------------------------------


def issue(identifier: str, *, relations: bool = False) -> dict:
    args = ["linear", "issue", identifier]
    if relations:
        args.append("--relations")
    r = run(*args)
    out = dict(r["issue"])
    if relations:
        out["relations"] = r.get("relations", [])
    return out


def state_type(iss: dict) -> str:
    """Linear の状態の種類：backlog / unstarted / started / completed / canceled。"""
    st = iss.get("state") or {}
    return st.get("type", "") if isinstance(st, dict) else ""


def state_name(iss: dict) -> str:
    st = iss.get("state") or {}
    return st.get("name", "") if isinstance(st, dict) else str(st)


def set_status(identifier: str, to: str) -> dict:
    return run("linear", "status", "set", identifier, "--to", to)


def comment(identifier: str, body: str) -> dict:
    return run("linear", "comment", "add", identifier, "--body", body)
