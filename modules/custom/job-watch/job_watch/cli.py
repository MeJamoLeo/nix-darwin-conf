"""cli — `job-watch run [--dry-run]`。パイプライン全体の組み立て。

流れ: 取得(source 単位で try/except) → 足切り → 新着だけ → 本文確認(上限あり) → 分類 → 出力＋state。
★ 本文確認の上限を超えた候補は seen にしない。翌日の実行が続きから拾う（落として忘れるより遅れて届く方がまし）。
"""
import argparse
import datetime as dt
import sys
import time
from . import config as C, sources, authcheck, state, report

TIER_RANK = lambda c: (c["tier"], not c.get("boost"))


def run(dry=False, now=None, fetch=True):
    now = now or dt.datetime.now()
    today = now.date()
    counts = {"scanned": 0, "filtered": 0, "excluded": 0, "new": 0, "deferred": 0}
    errors, cands = [], []
    jobs = [("Simplify/" + k, lambda k=k, u=u: sources.simplify(k, u, time.time(), counts)) for k, u in C.SIMPLIFY]
    jobs.append(("Oracle", lambda: sources.oracle(today, counts)))
    for name, fn in jobs:
        try:
            cands += fn()
        except Exception as e:  # 1 source の失敗で全体を止めない
            errors.append("%s: %s %s" % (name, type(e).__name__, str(e)[:80]))
    counts["filtered"] = len(cands)
    st = state.load()
    new = sorted((c for c in cands if state.is_new(st, c["key"])), key=TIER_RANK)
    kept, budget = [], (C.MAX_FETCHES if st["seen"] else C.MAX_FETCHES_BACKFILL)
    for c in new:
        if not fetch:
            c["cls"], c["evidence"] = authcheck._from_simplify(c, "UNKNOWN", "本文未確認")
        elif budget <= 0:
            counts["deferred"] += 1
            continue
        else:
            budget -= 1
            c["cls"], c["evidence"] = authcheck.check(c)
            time.sleep(0.2)  # 礼儀
        if c["cls"] == "EXCLUDE":
            counts["excluded"] += 1
        else:
            kept.append(c)
        if not dry:
            state.mark(st, c["key"], today, c["cls"])
    counts["new"] = len(kept)
    md = report.render(kept, counts, errors, now)
    if dry:
        print(md)
        return 0
    if kept or errors:
        path = report.append(today, md)
        print("report:", path)
    if kept:
        print("backlog:", "ok" if report.add_backlog(len(kept), today) else "FAILED (todo add)")
    state.save(st)
    print("counts:", counts, "errors:", errors)
    return 1 if errors and not cands else 0


def main():
    ap = argparse.ArgumentParser(prog="job-watch")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("run")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--no-fetch", action="store_true", help="本文確認を飛ばす（動作確認用）")
    a = ap.parse_args()
    return run(dry=a.dry_run, fetch=not a.no_fetch)


if __name__ == "__main__":
    sys.exit(main())
