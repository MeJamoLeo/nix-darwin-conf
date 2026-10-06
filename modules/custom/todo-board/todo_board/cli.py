"""cli — argparse とサブコマンドの振り分け（main）。"""
import argparse
import datetime as dt
import sys

from .store import current_day, day_path
from .daily import footer_line
from .commands import add, edit, pick, roll, show, sync_all
from . import blocks


def parse_date(s):
    return dt.date.today() if not s else dt.datetime.strptime(s, "%Y-%m-%d").date()


def main():
    ap = argparse.ArgumentParser(prog="todo-board")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("roll")
    p.add_argument("--date")
    p.add_argument("--no-fetch", action="store_true")
    p = sub.add_parser("path")
    p.add_argument("--date")
    sub.add_parser("pick")
    sub.add_parser("edit")
    sub.add_parser("show")
    sub.add_parser("open")  # edit の旧名（互換）
    sub.add_parser("sync")
    p = sub.add_parser("blocks")  # Claude 作業時間（record-blocks）を今日の行に (≈35m) で紐づける
    p.add_argument("--dry-run", action="store_true")
    sub.add_parser("canvas")  # sync の旧名（互換）
    pa = sub.add_parser("add")
    pa.add_argument("text", nargs="+")
    pa.add_argument("--due")
    pa.add_argument("--on")
    pa.add_argument("--size")
    a = ap.parse_args()
    if a.cmd == "roll":
        roll(parse_date(a.date), fetch=not a.no_fetch)
    elif a.cmd == "path":
        print(day_path(parse_date(a.date)))
    elif a.cmd == "pick":
        return pick(dt.date.today())
    elif a.cmd in ("sync", "canvas"):
        now = dt.datetime.now()
        day = current_day(now)  # 06:00 前で今日のファイルが無ければ前日のファイル（夜更かし中も締切の変更が届く）
        ok, _ = sync_all(day, now)
        if not ok:
            print(footer_line(day), file=sys.stderr)
        return 0 if ok else 1
    elif a.cmd == "blocks":
        with blocks.single_instance() as got:
            if not got:
                print("[blocks] another run is in progress; skipped")
                return 0
            return blocks.run(dt.datetime.now(), dry_run=a.dry_run)
    elif a.cmd == "show":
        return show(dt.date.today())
    elif a.cmd == "add":
        return add(dt.date.today(), a.text, a.due, a.on, a.size)
    else:
        edit(dt.date.today())
