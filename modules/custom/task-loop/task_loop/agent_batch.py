"""agent-batch：Agent issue を本人のタイミングで一斉に処理させる（Claude は呼ばない。起動するだけ）。

  task-loop agent-batch            今着手できる物を全部、同時に起動する
  task-loop agent-batch 8          8 本で頭打ち
  task-loop agent-batch --dry-run  拾われる順と本数だけ見せて、起動しない
  task-loop agent-batch --force    枠の判定を無視する

仕組み：Orca automation「Agent issue 無人処理」を `orca automations run` で N 回起動する。
起動された各セッションは `agent-pick --claim` で issue を取るので、ロックで直列化され、
同じ issue を2本が取ることはない（取った時点で In Progress になる）。
本数は「拾える issue の数」で頭打ちにする。枠（agent-pick の quota_ok）が足りなければ起動しない。
"""

from __future__ import annotations

import os
import sys

from . import agent_pick, orca, state

JOB = "agent-batch"
AUTOMATION = os.environ.get(
    "TASK_LOOP_AGENT_AUTOMATION", "c875a09b-c5a8-4660-a60f-942e2e8a1943"
)


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    force = "--force" in argv
    nums = [a for a in argv if a.isdigit()]
    want = int(nums[0]) if nums else None

    ok, msg = agent_pick.quota_ok()
    print(f"枠：{msg}")
    if not ok and not force:
        print("枠が足りないので起動しない（--force で無視できる）")
        state.record_run(JOB, True, f"skip quota: {msg}")
        return 1

    try:
        cs = agent_pick.candidates()
    except orca.OrcaError as e:
        print(f"ERROR {e}", file=sys.stderr)
        state.record_run(JOB, False, f"orca 失敗: {e}")
        return 1
    n = len(cs) if want is None else min(want, len(cs))
    if n == 0:
        print("拾える Agent issue が無い")
        state.record_run(JOB, True, "skip: 候補なし")
        return 1

    print(f"{n} 本起動する（候補 {len(cs)} 件）。拾われる見込み：")
    for iss in cs[:n]:
        print(f"  {iss['identifier']}  {iss['_due'] or '-'}  {iss['title'][:60]}")
    if dry:
        return 0

    started = 0
    for _ in range(n):
        try:
            orca.run("automations", "run", AUTOMATION)
            started += 1
        except orca.OrcaError as e:
            print(f"起動失敗：{e}", file=sys.stderr)
            break
    print(f"{started} 本起動した。進み具合：orca automations runs --id {AUTOMATION}")
    state.record_run(JOB, started == n, f"started {started}/{n}")
    return 0 if started == n else 1
