import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from task_loop import inventory as I  # noqa: E402

NOW = 1_800_000_000
DAY = 86400


class Schedule(unittest.TestCase):
    def test_interval(self):
        self.assertEqual(I.summarize_schedule({"StartInterval": 10800}), ("3時間ごと", 32400, False))
        self.assertEqual(I.summarize_schedule({"StartInterval": 60})[0], "1分ごと")

    def test_daily(self):
        s = I.summarize_schedule({"StartCalendarInterval": [{"Hour": 7, "Minute": 30}]})
        self.assertEqual(s, ("毎日 07:30", 2 * DAY, False))

    def test_weekly_dict(self):
        s = I.summarize_schedule({"StartCalendarInterval": {"Hour": 5, "Minute": 0, "Weekday": 0}})
        self.assertEqual(s, ("毎週日曜 05:00", 9 * DAY, False))

    def test_keepalive(self):
        self.assertEqual(I.summarize_schedule({"KeepAlive": True, "RunAtLoad": True}), ("常駐", None, True))

    def test_run_at_load_only(self):
        self.assertEqual(I.summarize_schedule({"RunAtLoad": True}), ("ログイン時に1回", None, False))


class Rows(unittest.TestCase):
    def test_user(self):
        t = "PID\tStatus\tLabel\n-\t0\torg.nix-community.home.mail-check\n12\t0\tcom.apple.x\n1976\t2\tcom.treo.foo\n"
        rows = I.parse_launchctl_rows(t, system=False)
        self.assertEqual([r["label"] for r in rows], ["org.nix-community.home.mail-check", "com.treo.foo"])
        self.assertEqual(rows[1], {"label": "com.treo.foo", "pid": 1976, "status": 2})
        self.assertIsNone(rows[0]["pid"])

    def test_system_excludes(self):
        t = "\t\t       0     78 \torg.nixos.youtube-gate-enforce\n\t\t   88530      0 \torg.nixos.nix-daemon\n\t\t0 0 org.nixos.activate-system\n\t\t 11534 - org.nixos.youtube-gate-pac\n"
        rows = I.parse_launchctl_rows(t, system=True)
        self.assertEqual([r["label"] for r in rows], ["org.nixos.youtube-gate-enforce", "org.nixos.youtube-gate-pac"])
        self.assertEqual(rows[0]["status"], 78)
        self.assertIsNone(rows[1]["status"])
        self.assertEqual(rows[1]["pid"], 11534)


class Health(unittest.TestCase):
    def row(self, pid=None, status=0):
        return {"label": "x", "pid": pid, "status": status}

    def test_keepalive_down(self):
        h, r = I.classify_launchd(self.row(), {"KeepAlive": True}, None, NOW)
        self.assertEqual(h, "bad")

    def test_keepalive_up_with_old_nonzero_status(self):
        h, _ = I.classify_launchd(self.row(pid=5, status=2), {"KeepAlive": True}, None, NOW)
        self.assertEqual(h, "ok")

    def test_nonzero_exit(self):
        h, r = I.classify_launchd(self.row(status=78), {"RunAtLoad": True}, None, NOW)
        self.assertEqual(h, "bad")
        self.assertIn("78", r[0])

    def test_interval_stale_and_fresh(self):
        p = {"StartInterval": 600}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 1799, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 1801, NOW)[0], "bad")

    def test_daily_two_days(self):
        p = {"StartCalendarInterval": [{"Hour": 7, "Minute": 0}]}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - DAY - 100, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 2 * DAY - 1, NOW)[0], "bad")

    def test_weekly_nine_days(self):
        p = {"StartCalendarInterval": {"Hour": 5, "Minute": 0, "Weekday": 0}}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 8 * DAY, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 10 * DAY, NOW)[0], "bad")

    def test_unknown_when_no_activity(self):
        self.assertEqual(I.classify_launchd(self.row(), {"StartInterval": 600}, None, NOW)[0], "unknown")

    def test_run_at_load_only_ok(self):
        self.assertEqual(I.classify_launchd(self.row(), {"RunAtLoad": True}, None, NOW)[0], "ok")

    def test_orca_disabled(self):
        self.assertEqual(I.classify_orca({"enabled": False})[0], "bad")
        self.assertEqual(I.classify_orca({"enabled": True})[0], "ok")


class Misc(unittest.TestCase):
    def test_describe_longest_first(self):
        self.assertEqual(I.describe("org.nix-community.home.com.treo.cp-dashboard-live"), "競プロのダッシュボード（常駐）")
        self.assertEqual(I.describe("org.nixos.youtube-gate-pac"), "YouTube 制限")
        self.assertEqual(I.describe("com.unknown.thing"), "com.unknown.thing")

    def test_task_loop_job(self):
        self.assertEqual(I.task_loop_job("org.nix-community.home.task-loop-completion-check"), "completion-check")
        self.assertIsNone(I.task_loop_job("org.nix-community.home.mail-check"))

    def test_rrule(self):
        self.assertEqual(I.summarize_rrule("FREQ=HOURLY;BYMINUTE=0"), "毎時 0分")
        self.assertEqual(I.summarize_rrule("FREQ=DAILY;BYHOUR=9;BYMINUTE=5"), "毎日 09:05")
        self.assertEqual(I.summarize_rrule("FREQ=YEARLY"), "FREQ=YEARLY")

    def test_find_identifier(self):
        self.assertEqual(I._find_identifier({"issue": {"x": 1, "identifier": "LIF-9"}}), "LIF-9")
        self.assertIsNone(I._find_identifier({"a": []}))


class Render(unittest.TestCase):
    def e(self, name, health, reasons=()):
        return {"name": name, "label": name, "kind": "launchd（ユーザー）", "schedule": "毎日 07:00",
                "last": NOW - 100, "health": health, "reasons": list(reasons)}

    def test_all_ok(self):
        body, n = I.render(NOW, [self.e("a", "ok")], [], [])
        self.assertEqual(n, 0)
        self.assertIn("全部正常", body.splitlines()[0])
        self.assertNotIn("## 不調", body)
        self.assertIn("- なし", body)

    def test_bad_first(self):
        planned = [{"identifier": "LIF-199", "title": "t", "state": {"name": "Todo", "type": "unstarted"}},
                   {"identifier": "LIF-1", "title": "done", "state": {"name": "Done", "type": "completed"}}]
        body, n = I.render(NOW, [self.e("a", "ok"), self.e("b|c", "bad", ["終了 1"])], planned, [])
        self.assertEqual(n, 1)
        self.assertIn("不調 1 件", body.splitlines()[0])
        self.assertLess(body.index("## 不調"), body.index("## 動いているもの"))
        self.assertIn("LIF-199（Todo）t", body)
        self.assertNotIn("LIF-1（", body)
        self.assertIn("b/c", body)  # 表のセル内の | は区切りを壊すので置換する

    def test_unknown_and_errors_not_bad(self):
        body, n = I.render(NOW, [self.e("a", "unknown", ["?"])], [], ["取得失敗X"])
        self.assertEqual(n, 0)
        self.assertIn("不明 2 件", body)
        self.assertIn("取得失敗: 取得失敗X", body)


if __name__ == "__main__":
    unittest.main()
