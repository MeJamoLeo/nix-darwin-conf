"""record-blocks の回帰テスト: python3 test_record_blocks.py（標準ライブラリのみ）。"""
import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("record_blocks", os.path.join(HERE, "bin", "record-blocks"))
spec = importlib.util.spec_from_loader("record_blocks", loader)
rb = importlib.util.module_from_spec(spec)
loader.exec_module(rb)

fails = []
def check(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  {extra}"))
    if not cond:
        fails.append(name)

UTC = dt.timezone.utc
def ev(ts, typ="user", text=None, entrypoint="cli", **kw):
    e = {"type": typ, "timestamp": ts, "entrypoint": entrypoint}
    if typ == "user":
        e["message"] = {"role": "user", "content": text if text is not None else "hello"}
    e.update(kw)
    return json.dumps(e)

def scan(lines):
    d = tempfile.mkdtemp()
    p = Path(d) / "s.jsonl"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    lo = dt.datetime(2026, 10, 4, 0, 0, tzinfo=UTC)
    return rb.scan_session(p, lo, lo + dt.timedelta(days=1), dt.timedelta(minutes=30))

# --- end < start のバグ（2026-10-04 の d44416fc）: 並びの乱れた古い timestamp の行が1本混ざる
segs = scan([
    ev("2026-10-04T10:00:00.000Z", text="start work"),
    ev("2026-10-04T10:05:00.000Z", "assistant"),
    ev("2026-10-04T05:51:39.268Z", "attachment"),   # 5時間前の異物（resume の再掲）
    ev("2026-10-04T10:06:00.000Z", "assistant"),
])
check("stray old timestamp does not split the block", len(segs) == 1, segs)
check("end >= start and end is the real last activity", segs and segs[0]["end"] >= segs[0]["start"] and segs[0]["end"].minute == 6, segs)
segs = scan([ev("2026-10-04T10:00:00.955Z", text="a"), ev("2026-10-04T10:00:00.807Z", text="b"), ev("2026-10-04T10:10:00Z", "assistant")])
check("a few ms backwards is kept (both prompts counted)", len(segs) == 1 and segs[0]["prompts"] == 2, segs)

# --- 人の作業かどうか（構造化フィールドで判定）
segs = scan([ev("2026-10-04T11:00:00Z", text="# 実行時パラメータ", entrypoint="sdk-cli"), ev("2026-10-04T11:05:00Z", "assistant", entrypoint="sdk-cli")])
check("sdk-cli (claude -p) block is not interactive", segs[0]["interactive"] is False and segs[0]["entrypoint"] == "sdk-cli")
segs = scan([ev("2026-10-04T11:00:00Z", text="<task-notification>\n<task-id>x</task-id>"), ev("2026-10-04T11:05:00Z", "assistant")])
check("task-notification-only block: no trigger, not interactive", segs[0]["trigger"] is None and segs[0]["interactive"] is False, segs)
segs = scan([ev("2026-10-04T11:00:00Z", text="real question"), ev("2026-10-04T11:05:00Z", "assistant")])
check("normal cli block is interactive", segs[0]["interactive"] is True and segs[0]["trigger"] == "real question")

# --- 分類の手がかり（発話サンプル・科目コード・触ったファイル）
asst = json.dumps({"type": "assistant", "timestamp": "2026-10-04T11:02:00Z", "entrypoint": "cli",
                   "message": {"content": [{"type": "tool_use", "input": {"file_path": "/x/Store/20_Courses/CS4355/ex4.md"}}]}})
segs = scan([ev("2026-10-04T11:00:00Z", text="CS 4355 の dp を解く"), asst, ev("2026-10-04T11:05:00Z", text="つづき")])
check("samples: user prompts kept (capped), course code from prompt text", segs[0]["samples"] == ["CS 4355 の dp を解く", "つづき"] and segs[0]["course_codes"] == ["CS4355"], segs[0])
check("files: tool_use file_path collected", segs[0]["files"] == ["/x/Store/20_Courses/CS4355/ex4.md"], segs[0])
segs = scan([ev("2026-10-04T11:00:00Z", text="hello"), ev("2026-10-04T11:01:00Z", "attachment", text=None, note="CS2315 CS3360")])
check("codes: only typed prompts are counted", segs[0]["course_codes"] == [], segs[0])

print("\nFAILS:", fails)
sys.exit(1 if fails else 0)
