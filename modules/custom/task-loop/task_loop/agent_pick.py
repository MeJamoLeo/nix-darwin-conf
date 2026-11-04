"""agent-pick：無人 automation が次に処理する `Agent` issue を1件選ぶ（Claude は呼ばない）。

  task-loop agent-pick            選んだ issue の ID を1行出す（無ければ何も出さず exit 1）
  task-loop agent-pick --claim    選んだ issue をその場で In Progress にしてから ID を出す。
                                  ロックで直列化するので、同時に何本走らせても同じ issue を2本が取らない
                                  （agent-batch で一斉に走らせるときの入口）
  task-loop agent-pick --check    Orca automation の precheck 用。
                                  「拾える issue がある」かつ「枠が余っている」なら exit 0、それ以外は exit 1

拾える issue：ラベル `Agent`・状態 Todo・`blocked by` の issue が全部 Done/Canceled・
本文の `not-before: YYYY-MM-DD` があればその日以降。
順番：期限（issue か親の dueDate）が近い順 → priority（1=Urgent が先、0=なしは最後）→ 古い順。

枠（vault の task-execution-redesign-linear-orca §2026-10-31）：
  5時間枠：使用率 ＜ 100 − 50 ×（リセットまでの残り秒 ÷ 18000）
  週枠  ：使用率 ≦ 週の経過率（%）
  数字は ~/.cache/claude-ratelimits/latest.json（statusline の中継が書く）。
  リセット時刻を過ぎていたら使用率0とみなす。ファイルが無い・壊れている → 走らせない（安全側）。
"""

from __future__ import annotations

import fcntl
import json
import re
import sys
import time
from pathlib import Path

from . import orca, state

JOB = "agent-pick"
TEAM = "LIF"
RATE_FILE = Path.home() / ".cache/claude-ratelimits/latest.json"
FIVE_H = 5 * 3600
WEEK = 7 * 86400
DONEISH = {"completed", "canceled"}


def quota_ok(now: float | None = None) -> tuple[bool, str]:
    now = time.time() if now is None else now
    try:
        rl = json.loads(RATE_FILE.read_text())["rate_limits"]
        five, week = rl["five_hour"], rl["seven_day"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as e:
        return False, f"枠のファイルを読めない（{type(e).__name__}）"

    def used(w: dict) -> float:
        return 0.0 if now >= w["resets_at"] else float(w["used_percentage"])

    five_left = max(0.0, five["resets_at"] - now)
    five_line = 100 - 50 * min(1.0, five_left / FIVE_H)
    five_used = used(five)

    if now >= week["resets_at"]:
        week_used, week_elapsed = 0.0, 0.0
    else:
        week_used = float(week["used_percentage"])
        week_elapsed = 100 * (WEEK - (week["resets_at"] - now)) / WEEK

    msg = (
        f"5h {five_used:.0f}%（線 {five_line:.0f}%）・"
        f"週 {week_used:.0f}%（経過 {week_elapsed:.0f}%）"
    )
    return (five_used < five_line and week_used <= week_elapsed), msg


def _parent_id(iss: dict) -> str | None:
    m = re.search(r"^parent:\s*([A-Z]+-\d+)", iss.get("description") or "", re.M)
    return m.group(1) if m else None


def candidates() -> list[dict]:
    issues = orca.run(
        "linear", "list-issues", "--team", TEAM, "--label", "Agent", "--state", "Todo"
    )["issues"]
    parent_due: dict[str, str | None] = {}
    ready = []
    for iss in issues:
        full = orca.issue(iss["identifier"], relations=True)
        blockers = [
            r["relatedIssue"]["identifier"]
            for r in full.get("relations", [])
            if r.get("relationship") == "blockedBy"
        ]
        if any(orca.state_type(orca.issue(b)) not in DONEISH for b in blockers):
            continue
        # 本文の `not-before: YYYY-MM-DD` より前は拾わない（例：審理の結果待ち）
        nb = re.search(r"^not-before:\s*(\d{4}-\d{2}-\d{2})", iss.get("description") or "", re.M)
        if nb and time.strftime("%Y-%m-%d") < nb.group(1):
            continue
        due = iss.get("dueDate")
        pid = _parent_id(iss)
        if not due and pid:
            if pid not in parent_due:
                try:
                    parent_due[pid] = orca.issue(pid).get("dueDate")
                except orca.OrcaError:
                    parent_due[pid] = None
            due = parent_due[pid]
        iss["_due"] = due
        ready.append(iss)

    def key(i: dict):
        pr = i.get("priority") or 0
        return (i["_due"] or "9999-12-31", pr if pr else 9, i.get("createdAt", ""))

    return sorted(ready, key=key)


LOCK = state.ROOT / "agent-pick.lock"


def claim() -> str | None:
    """候補の先頭を In Progress にして返す。ロック中は他の claim を待たせる。"""
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        cs = candidates()
        if not cs:
            return None
        ident = cs[0]["identifier"]
        orca.set_status(ident, "In Progress")
        return ident


def main(argv: list[str]) -> int:
    if "--claim" in argv:
        try:
            ident = claim()
        except orca.OrcaError as e:
            print(f"ERROR {e}", file=sys.stderr)
            state.record_run(JOB, False, f"claim 失敗: {e}")
            return 1
        if not ident:
            return 1
        state.record_run(JOB, True, f"claim: {ident}")
        print(ident)
        return 0
    check = "--check" in argv
    if check:
        ok, msg = quota_ok()
        if not ok:
            print(f"skip: 枠が足りない（{msg}）")
            state.record_run(JOB, True, f"skip quota: {msg}")
            return 1
    try:
        cs = candidates()
    except orca.OrcaError as e:
        print(f"ERROR {e}", file=sys.stderr)
        state.record_run(JOB, False, f"orca 失敗: {e}")
        return 1
    if not cs:
        if check:
            print("skip: 拾える Agent issue が無い")
            state.record_run(JOB, True, "skip: 候補なし")
        return 1
    top = cs[0]
    if check:
        print(f"run: {top['identifier']} ほか {len(cs) - 1} 件（{quota_ok()[1]}）")
        state.record_run(JOB, True, f"run: {top['identifier']}（候補 {len(cs)}）")
    else:
        print(top["identifier"])
    return 0
