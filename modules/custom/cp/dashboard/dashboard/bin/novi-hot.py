#!/usr/bin/env python3
"""novi-hot.py — 「もうすぐ変わるはずの NoviSteps トピック」を選んで task_id を印字する。

背景（2026-08-13 の実測）:
  NoviSteps のステータスは **AC の瞬間には変わらない**。abc468_c は AC の18秒後に取得した時点で
  まだ `ns`（未着手）で、3.8時間後に取り直したら `ac` になっていた。`ac_with_editorial`（解説AC）は
  AtCoder の提出データから自動導出できない値なので、変化は AC イベントとは別のタイミングで来る。
  一方 `fetch_novisteps.py --one` は 1 サイクル 1 冊なので、65 冊の一周は約32.5時間。
  結果として「今マークした分が盤面に出るまで最大32時間」になっていた。

方針:
  変化の**時刻**は観測できないが**状態**は観測できる。だから
  「ローカル（solve_times.jsonl）では AC 済みなのに novisteps.json 上でまだ AC になっていない」
  という**差分が消えるまで**、その task を含む workbook だけを追加で取り直す。
  マークされた瞬間に差分が消えて自動的に止まる（固定スケジュールの再送と違って当て推量が要らない）。

暴走を止める2つの条件（advisor 指摘・2026-08-13）:
  (a) 打ち切りの起点は **AC 時刻**。これが無いと、マークされないまま放置された過去の AC
      （実在した：abc357_c は5.5日前に AC 済みだが NoviSteps 上は `wa` のまま）が hot 集合に
      永久に居座り、30分ごとに空振りポーリングし続ける。
  (b) AC からの経過で**減衰**させる。毎サイクル×3冊×3日＝最大432リクエストは、非公式の個人運営
      サービス相手に現行負荷（48/日）を数倍にする。下の DECAY で1件あたり最大約25回に抑える。

出力: 選ばれた workbook を代表する task_id を1行1件（`--task` は workbook 単位に畳まれるので
      1 冊につき1件でよい）。該当なしなら何も出力しない（正常・終了コード0）。
"""

import json
import os
import sys
import time
from pathlib import Path

CACHE = Path(os.environ.get("CP_DASH_CACHE", Path.home() / ".cache" / "cp-dashboard"))
LIVE = CACHE / "solve_times.jsonl"
NOVI = CACHE / "novisteps.json"

AC_STATUSES = ("ac", "ac_with_editorial")   # これになったら差分は解消＝hot から外れる
MAX_WORKBOOKS = 3                            # 1 サイクルに追加で取る上限

# (AC からの経過秒, その間の最小取得間隔秒)。上から順に最初に当たったものを使う。
# 経過が最後の閾値を超えたら hot から外す（＝通常の 32.5h 周回に任せる）。
DECAY = (
    (3 * 3600,      0),          # 最初の3時間は毎サイクル（30分）
    (24 * 3600,     2 * 3600),   # 24時間までは2時間ごと
    (72 * 3600,     6 * 3600),   # 72時間までは6時間ごと
)


def load_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError, ValueError):
        return default


def local_acs():
    """solve_times.jsonl（LIVE のみ）から {task_id: 最新の ac_epoch}。
    SEED は混ぜない——x1nano 由来の過去記録であり、到着待ちのデータではない。"""
    out = {}
    try:
        lines = LIVE.read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        tid, ac_e = rec.get("task_id"), rec.get("ac_epoch")
        if tid and isinstance(ac_e, (int, float)):
            out[tid] = max(out.get(tid, 0), int(ac_e))
    return out


def parse_iso(s):
    from datetime import datetime
    try:
        return datetime.fromisoformat(s).timestamp()
    except (TypeError, ValueError):
        return None


def main():
    now = time.time()
    acs = local_acs()
    if not acs:
        return 0
    novi = load_json(NOVI, {}) or {}
    workbooks = novi.get("workbooks") or {}
    if not workbooks:
        return 0

    # workbook ごとに「差分が残っている task のうち最も新しい AC」と取得時刻を集める。
    cand = {}
    for slug, wb in workbooks.items():
        if not isinstance(wb, dict):
            continue
        newest_ac = 0
        rep = None
        for t in wb.get("tasks", []):
            tid = t.get("task_id")
            if tid not in acs or t.get("status") in AC_STATUSES:
                continue                      # 未AC でない or もうマーク済み＝差分なし
            if acs[tid] > newest_ac:
                newest_ac, rep = acs[tid], tid
        if rep is None:
            continue
        age = now - newest_ac
        interval = None
        for limit, iv in DECAY:
            if age < limit:
                interval = iv
                break
        if interval is None:
            continue                          # 打ち切り（起点＝AC 時刻）
        fetched = parse_iso(wb.get("fetched_at"))
        if fetched is not None and now - fetched < interval:
            continue                          # まだ間隔を満たしていない
        cand[slug] = (fetched if fetched is not None else 0, rep)

    # 取得が古い順に上限まで。
    for slug, (_, rep) in sorted(cand.items(), key=lambda kv: kv[1][0])[:MAX_WORKBOOKS]:
        print(rep)
    return 0


if __name__ == "__main__":
    sys.exit(main())
