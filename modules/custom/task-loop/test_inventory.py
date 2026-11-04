import os
import sys
import unittest
from datetime import date, datetime

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
        # ログだけで古い場合は不調にせず不明（2026-11-03 の誤報の再発防止）。
        p = {"StartInterval": 600}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 1799, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 1801, NOW)[0], "unknown")

    def test_daily_two_days(self):
        p = {"StartCalendarInterval": [{"Hour": 7, "Minute": 0}]}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - DAY - 100, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 2 * DAY - 1, NOW)[0], "unknown")

    def test_weekly_nine_days(self):
        p = {"StartCalendarInterval": {"Hour": 5, "Minute": 0, "Weekday": 0}}
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 8 * DAY, NOW)[0], "ok")
        self.assertEqual(I.classify_launchd(self.row(), p, NOW - 10 * DAY, NOW)[0], "unknown")

    def test_unknown_when_no_activity(self):
        self.assertEqual(I.classify_launchd(self.row(), {"StartInterval": 600}, None, NOW)[0], "unknown")

    def test_run_at_load_only_ok(self):
        self.assertEqual(I.classify_launchd(self.row(), {"RunAtLoad": True}, None, NOW)[0], "ok")

    def test_orca_disabled(self):
        self.assertEqual(I.classify_orca({"enabled": False})[0], "bad")
        self.assertEqual(I.classify_orca({"enabled": True})[0], "ok")


SPAWN_FAIL = """system/org.nixos.x = {
	state = not running
	runs = 3
	last exit code = 78
	spawn scheduled = 1
}"""
HEALTHY = """gui/501/x = {
	state = not running
	runs = 5
	last exit code = 0
}"""


class Evidence(unittest.TestCase):
    P = {"StartInterval": 1800}

    def row(self, pid=None, status=0):
        return {"label": "x", "pid": pid, "status": status}

    def art(self, age, max_age=7200):
        return {"name": "update.log", "max_age": max_age, "mtime": NOW - age}

    def test_false_alarm_old_log_fresh_artifact_is_ok(self):
        lc = I.parse_launchctl_print(HEALTHY)
        h, r = I.classify_launchd(self.row(), self.P, NOW - 120 * DAY, NOW, lc, self.art(600))
        self.assertEqual((h, r), ("ok", []))

    def test_log_only_old_is_unknown_not_bad(self):
        h, r = I.classify_launchd(self.row(), self.P, NOW - 90 * DAY, NOW, I.parse_launchctl_print(HEALTHY), None)
        self.assertEqual(h, "unknown")
        self.assertTrue(r)

    def test_stale_artifact_is_bad(self):
        h, r = I.classify_launchd(self.row(), self.P, NOW - 10, NOW, None, self.art(3 * 3600))
        self.assertEqual(h, "bad")
        self.assertIn("update.log", r[0])

    def test_spawn_failure_parse(self):
        lc = I.parse_launchctl_print(SPAWN_FAIL)
        self.assertEqual(lc, {"state": "not running", "last_exit": 78, "spawn_failure": True, "runs": 3})
        self.assertTrue(I.parse_launchctl_print("job state = penalty box\n")["spawn_failure"])
        self.assertFalse(I.parse_launchctl_print(HEALTHY)["spawn_failure"])
        # 終了コード 0 の spawn scheduled は起動失敗とみなさない
        self.assertFalse(I.parse_launchctl_print("spawn scheduled\nlast exit code = 0\n")["spawn_failure"])
        h, r = I.classify_launchd(self.row(status=None), self.P, None, NOW, lc, None)
        self.assertEqual(h, "bad")
        self.assertTrue(any("起動に失敗" in x for x in r))

    def test_last_exit_from_launchctl_print(self):
        lc = {"state": "not running", "last_exit": 2, "spawn_failure": False}
        self.assertEqual(I.classify_launchd(self.row(status=None), self.P, NOW, NOW, lc, self.art(10))[0], "bad")

    def test_artifact_spec_longest_first(self):
        self.assertTrue(I.artifact_spec("org.x.com.treo.cp-dashboard-stopwatch")["path"].endswith("poller.lock"))
        self.assertTrue(I.artifact_spec("org.x.com.treo.cp-dashboard")["path"].endswith("update.log"))
        self.assertIsNone(I.artifact_spec("org.x.omniwm"))


def ent(key, health, name=None, since=None):
    return {"key": key, "name": name or key, "label": key, "kind": "launchd（ユーザー）", "schedule": "毎日",
            "last": None, "health": health, "reasons": ["理由"], "since": since}


TODAY = date(2026, 11, 3)


class History(unittest.TestCase):
    def test_dedupe_open_issue_not_recreated(self):
        jobs = {"a": {"investigation": "LIF-300"}, "b": {}}
        todo = I.plan_investigations([ent("a", "bad"), ent("b", "bad"), ent("c", "ok")], jobs, lambda i: True)
        self.assertEqual([e["key"] for e in todo], ["b"])

    def test_closed_issue_recreated_when_bad_again(self):
        jobs = {"a": {"investigation": "LIF-300"}}
        todo = I.plan_investigations([ent("a", "bad")], jobs, lambda i: False)
        self.assertEqual([e["key"] for e in todo], ["a"])

    def test_healthy_or_unknown_gets_no_issue(self):
        self.assertEqual(I.plan_investigations([ent("a", "ok"), ent("b", "unknown")], {}, lambda i: False), [])

    def test_issue_text(self):
        e = ent("com.x.job", "bad", name="テスト")
        self.assertEqual(I.investigation_title(e), "仕組みの不調を調べる：テスト")
        body = I.investigation_body(e, TODAY)
        for w in ("com.x.job", "理由", "sudo", "launchctl bootout", "削除"):
            self.assertIn(w, body)

    def test_candidate_after_14_days(self):
        jobs = {"a": {"first_unhealthy": "2026-10-20"}, "b": {"first_unhealthy": "2026-10-21"}}
        new, cands, _ = I.update_history(jobs, [ent("a", "bad"), ent("b", "bad")], TODAY)
        self.assertEqual([c["key"] for c in cands], ["a"])  # a=14日, b=13日
        self.assertEqual(cands[0]["days"], 14)
        body, _ = I.render(NOW, [ent("a", "bad")], [], [], None, cands, [])
        self.assertIn("## 消す候補（2週間止まっていて困っていない）", body)
        self.assertIn("止まっていても困らなかったなら要らない。残すなら理由を、消すならそう返事して。", body)

    def test_no_candidate_section_when_empty(self):
        body, _ = I.render(NOW, [ent("a", "ok")], [], [])
        self.assertNotIn("消す候補", body)

    def test_first_unhealthy_starts_today_or_from_evidence(self):
        since = int(datetime(2026, 7, 3, 12).timestamp())
        new, cands, _ = I.update_history({}, [ent("a", "bad"), ent("b", "bad", since=since)], TODAY)
        self.assertEqual(new["a"]["first_unhealthy"], "2026-11-03")
        self.assertEqual(new["b"]["first_unhealthy"], "2026-11-03")  # 成果物の日付で遡らない
        self.assertEqual(cands, [])  # 初日に消す候補へ飛ばない

    def test_recovery_clears_and_is_reported(self):
        jobs = {"a": {"first_unhealthy": "2026-10-30", "investigation": "LIF-300"}}
        new, cands, rec = I.update_history(jobs, [ent("a", "ok")], TODAY)
        self.assertNotIn("first_unhealthy", new["a"])
        self.assertEqual(new["a"]["investigation"], "LIF-300")
        self.assertEqual(rec[0]["issue"], "LIF-300")
        self.assertEqual(cands, [])

    def test_unknown_keeps_history(self):
        jobs = {"a": {"first_unhealthy": "2026-10-30"}}
        new, _, _ = I.update_history(jobs, [ent("a", "unknown")], TODAY)
        self.assertEqual(new["a"]["first_unhealthy"], "2026-10-30")


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



class DedupeByTitleTest(unittest.TestCase):
    def test_existing_title_is_not_recreated_and_id_recovered(self):
        from task_loop import inventory as I
        e = ent("a", "bad", name="X")
        jobs = {}
        todo = I.plan_investigations([e], jobs, lambda i: False,
                                     existing={I.investigation_title(e): "LIF-900"})
        self.assertEqual(todo, [])
        self.assertEqual(jobs["a"]["investigation"], "LIF-900")


class DryRunNoWritesTest(unittest.TestCase):
    def test_dry_run_never_writes(self):
        from unittest import mock
        from task_loop import inventory as I
        def fake_run(*a):
            if a[:2] in (("linear", "create"), ("linear", "save-issue")) or a[:2] == ("linear", "status"):
                raise AssertionError(f"dry-run で書き込み: {a}")
            return {"issues": []}
        bad = ent("a", "bad", name="X")
        with mock.patch.object(I.orca, "run", side_effect=fake_run), \
             mock.patch.object(I, "collect_launchd", return_value=([bad], [])), \
             mock.patch.object(I, "collect_orca", return_value=([], [])), \
             mock.patch.object(I, "collect_planned", return_value=([], [])), \
             mock.patch.object(I.state, "load", return_value={"issue": "LIF-211"}), \
             mock.patch.object(I.state, "save", side_effect=AssertionError("dry-run で state 保存")), \
             mock.patch("builtins.print"):
            self.assertEqual(I.main([]), 0)


class TooFewRunsTest(unittest.TestCase):
    def test_interval_job_barely_ran_is_bad(self):
        from task_loop import inventory as inv
        now = 1_000_000
        lc = {"runs": 1, "loaded_at": now - 5 * 86400, "last_exit": 0, "state": "not running"}
        self.assertIsNotNone(inv.too_few_runs({"StartInterval": 600}, lc, now))
        self.assertIsNone(inv.too_few_runs({"StartInterval": 600, "KeepAlive": True}, lc, now))

    def test_sleepy_mac_is_not_flagged(self):
        from task_loop import inventory as inv
        now = 1_000_000  # 1日・10分ごと＝予定144回。スリープで実績20回でも 1/10 以上なので不調にしない
        lc = {"runs": 20, "loaded_at": now - 86400}
        self.assertIsNone(inv.too_few_runs({"StartInterval": 600}, lc, now))

    def test_recently_loaded_is_fine(self):
        from task_loop import inventory as inv
        now = 1_000_000
        lc = {"runs": 1, "loaded_at": now - 1200, "last_exit": 0}
        self.assertIsNone(inv.too_few_runs({"StartInterval": 600}, lc, now))

    def test_parse_runs(self):
        from task_loop import inventory as inv
        d = inv.parse_launchctl_print("\tstate = not running\n\truns = 51\n\tlast exit code = 0\n")
        self.assertEqual(d["runs"], 51)

if __name__ == "__main__":
    unittest.main()
