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
            f'<td><span class="label">{status}</span></td></tr>')


class AtcoderParserTest(unittest.TestCase):
    START = datetime(2026, 7, 5, 11, 0, 0, tzinfo=JST).timestamp()

    def probe(self, html):
        fetched = html.encode() if html is not None else None
        with mock.patch.object(sp, "_fetch", return_value=fetched):
            return sp.first_ac_epoch_atcoder(USER, CONTEST, TASK,
                                             self.START, "dummy")

    def test_first_ac_after_start(self):
        html = ("<html><table>"
                + row(TASK, USER, "AC", "2026-07-05 10:00:00+0900")   # start前
                + row(TASK, USER, "AC", "2026-07-05 12:34:56+0900")   # 初AC
                + row(TASK, USER, "AC", "2026-07-05 13:00:00+0900")
                + row(TASK, USER, "WA", "2026-07-05 12:00:00+0900")
                + row("abc086_b", USER, "AC", "2026-07-05 12:10:00+0900")
                + row(TASK, "someoneelse", "AC", "2026-07-05 12:05:00+0900")
                + "</table></html>")
        ac, ok = self.probe(html)
        self.assertTrue(ok)
        expect = int(datetime(2026, 7, 5, 12, 34, 56, tzinfo=JST).timestamp())
        self.assertEqual(ac, expect)

    def test_wa_only_is_authoritative_none(self):
        ac, ok = self.probe(
            "<table>" + row(TASK, USER, "WA", "2026-07-05 12:00:00+0900") + "</table>")
        self.assertEqual((ac, ok), (None, True))

    def test_sign_in_redirect_is_not_authoritative(self):
        ac, ok = self.probe("<html><title>Sign In - AtCoder</title></html>")
        self.assertEqual((ac, ok), (None, False))

    def test_fetch_failure_is_not_authoritative(self):
        ac, ok = self.probe(None)
        self.assertEqual((ac, ok), (None, False))

    def test_broken_fixtime_falls_back(self):
        # AC行はあるのに時刻が取れない＝ページ構造変化 → 断定せず fallback
        broken = row(TASK, USER, "AC", "x").replace(
            'class="fixtime fixtime-second"', 'class="renamed"')
        ac, ok = self.probe("<table>" + broken + "</table>")
        self.assertEqual((ac, ok), (None, False))

    def test_unparsable_time_falls_back(self):
        ac, ok = self.probe(
            "<table>" + row(TASK, USER, "AC", "not a timestamp") + "</table>")
        self.assertEqual((ac, ok), (None, False))


class SessionSourceTest(unittest.TestCase):
    def test_env_override(self):
        with mock.patch.dict(os.environ, {"CP_ATCODER_SESSION": "tok"}):
            self.assertEqual(sp.atcoder_session(), "tok")


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
