#!/usr/bin/env python3
"""Regression tests for stopwatch_poll.py (network-free; _fetch is mocked).

Run: cd upstream && python3 -m unittest test_stopwatch_poll -v
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stopwatch_poll as sp  # noqa: E402

JST = timezone(timedelta(hours=9))
USER, CONTEST, TASK = "MeJamoLeo", "abc086", "abc086_a"


def row(task, user, status, ts, contest=CONTEST):
    return (f'<tr><td><time class="fixtime fixtime-second">{ts}</time></td>'
            f'<td><a href="/contests/{contest}/tasks/{task}">T</a></td>'
            f'<td><a href="/users/{user}">{user}</a></td>'
            f'<td><span class="label label-success">{status}</span></td></tr>')


class ScanAtcoderRowsTest(unittest.TestCase):
    START = datetime(2026, 7, 5, 11, 0, 0, tzinfo=JST).timestamp()

    def epoch(self, h, m, s):
        return int(datetime(2026, 7, 5, h, m, s, tzinfo=JST).timestamp())

    def probe(self, html):
        fetched = html.encode() if html is not None else None
        with mock.patch.object(sp, "_fetch", return_value=fetched):
            return sp.scan_atcoder_rows(USER, CONTEST, TASK, self.START, "dummy")

    def test_first_ac_after_start(self):
        html = ("<html><table>"
                + row(TASK, USER, "AC", "2026-07-05 10:00:00+0900")   # start前
                + row(TASK, USER, "AC", "2026-07-05 12:34:56+0900")   # 初AC
                + row(TASK, USER, "AC", "2026-07-05 13:00:00+0900")
                + row(TASK, USER, "WA", "2026-07-05 12:00:00+0900")
                + row("abc086_b", USER, "AC", "2026-07-05 12:10:00+0900")
                + row(TASK, "someoneelse", "AC", "2026-07-05 12:05:00+0900")
                + "</table></html>")
        p = self.probe(html)
        self.assertIsNotNone(p)
        self.assertEqual(p["first_ac"], self.epoch(12, 34, 56))
        self.assertEqual(p["last_wa"], self.epoch(12, 0, 0))
        self.assertIsNone(p["judging_at"])

    def test_wa_only_keeps_running(self):
        p = self.probe(
            "<table>" + row(TASK, USER, "WA", "2026-07-05 12:00:00+0900") + "</table>")
        self.assertIsNone(p["first_ac"])
        self.assertEqual(p["last_wa"], self.epoch(12, 0, 0))

    def test_wj_row_is_judging(self):
        html = ("<table>"
                + row(TASK, USER, "WJ", "2026-07-05 12:20:00+0900")
                + "</table>")
        p = self.probe(html)
        self.assertIsNone(p["first_ac"])
        self.assertEqual(p["judging_at"], self.epoch(12, 20, 0))

    def test_progress_row_is_judging(self):
        p = self.probe(
            "<table>" + row(TASK, USER, "3/15", "2026-07-05 12:21:00+0900") + "</table>")
        self.assertEqual(p["judging_at"], self.epoch(12, 21, 0))

    def test_final_verdicts_are_not_judging(self):
        for verdict in ("TLE", "RE", "CE", "MLE"):
            p = self.probe(
                "<table>" + row(TASK, USER, verdict, "2026-07-05 12:22:00+0900") + "</table>")
            self.assertIsNone(p["judging_at"], verdict)
            self.assertIsNone(p["first_ac"], verdict)

    def test_sign_in_redirect_is_none(self):
        self.assertIsNone(self.probe("<html><title>Sign In - AtCoder</title></html>"))

    def test_fetch_failure_is_none(self):
        self.assertIsNone(self.probe(None))

    def test_broken_fixtime_is_none(self):
        # 対象行はあるのに時刻が取れない＝構造変化 → 断定せず fallback
        broken = row(TASK, USER, "AC", "x").replace(
            'class="fixtime fixtime-second"', 'class="renamed"')
        self.assertIsNone(self.probe("<table>" + broken + "</table>"))

    def test_unparsable_time_is_none(self):
        self.assertIsNone(self.probe(
            "<table>" + row(TASK, USER, "AC", "not a timestamp") + "</table>"))


class SessionSourceTest(unittest.TestCase):
    def test_env_override(self):
        with mock.patch.dict(os.environ, {"CP_ATCODER_SESSION": "tok"}):
            self.assertEqual(sp.atcoder_session(), "tok")


class TestedMarkerTest(unittest.TestCase):
    def test_marker_matches_task_within_window(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "test-passed.json"
            marker.write_text(json.dumps({"task_id": TASK, "passed_at": 1000}))
            with mock.patch.object(sp, "MARKER", marker):
                self.assertEqual(sp.tested_at_for(TASK, 1300), 1000)
                self.assertIsNone(sp.tested_at_for(TASK, 1000 + sp.TESTED_SHOW_S + 1))
                self.assertIsNone(sp.tested_at_for("abc086_b", 1300))


class SigTest(unittest.TestCase):
    def test_resubmit_advances_submitted_at(self):
        # 再提出で仮停止時刻が進んだら盤面を再描画する（judging フラグは同じでも）
        a = {"status": "running", "task_id": TASK, "start": 1,
             "judging": True, "submitted_at": 100}
        self.assertNotEqual(sp.sig(a), sp.sig({**a, "submitted_at": 200}))
        self.assertEqual(sp.sig(a), sp.sig({**a, "updated_at": 999}))


class DatasetAppendTest(unittest.TestCase):
    def test_dedupe_on_task_and_start(self):
        rec = {"task_id": TASK, "contest": CONTEST, "start": 100,
               "ac_epoch": 700, "elapsed": 600, "grade": "Q4"}
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(sp, "CACHE", Path(d)), \
                 mock.patch.object(sp, "DATASET", Path(d) / "solve_times.jsonl"):
                self.assertTrue(sp.append_dataset(dict(rec)))
                self.assertFalse(sp.append_dataset(dict(rec)))
                lines = (Path(d) / "solve_times.jsonl").read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["elapsed"], 600)


if __name__ == "__main__":
    unittest.main()
