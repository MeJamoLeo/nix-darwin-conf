"""ジョブの実行記録と小さな永続状態。watchdog がここを読む。

置き場所：~/.local/state/task-loop/
  status/<job>.json   … last_run / last_ok / ok / summary（watchdog が最終成功時刻を見る）
  <job>.json          … ジョブ固有の状態（同じコメントを毎日付けないための記録など）
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

ROOT = Path(os.environ.get("TASK_LOOP_STATE", Path.home() / ".local/state/task-loop"))


def _write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n")
    os.replace(tmp, path)


def load(job: str) -> dict:
    p = ROOT / f"{job}.json"
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save(job: str, data: dict) -> None:
    _write(ROOT / f"{job}.json", data)


def record_run(job: str, ok: bool, summary: str) -> None:
    p = ROOT / "status" / f"{job}.json"
    try:
        prev = json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        prev = {}
    now = int(time.time())
    data = {
        "job": job,
        "last_run": now,
        "last_ok": now if ok else prev.get("last_ok"),
        "ok": ok,
        "summary": summary,
    }
    _write(p, data)
