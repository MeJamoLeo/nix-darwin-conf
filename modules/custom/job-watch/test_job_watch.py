import datetime as dt
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ["JOB_WATCH_DIR"] = tempfile.mkdtemp()  # 本物の ~/Store を触らない

from job_watch import authcheck, classify as K, cli, config as C, filters as F, net, report, state  # noqa: E402

NOW = 1_800_000_000


def rec(**kw):
    d = {"id": "1", "company_name": "Acme", "title": "Software Engineer", "active": True, "is_visible": True, "date_posted": NOW - 86400,
         "url": "https://x.example/1", "locations": ["Austin, TX"], "sponsorship": "Other", "category": "Software", "degrees": ["Bachelor's"]}
    d.update(kw)
    return d


class Classifier(unittest.TestCase):
    def test_oracle_exclude(self):
        t = "Oracle is not in a position now, or in the future, to sponsor or accept (EAD, OPT, CPT, I-20, F-1 visa stamp) for this role."
        self.assertEqual(K.classify(t)[0], "EXCLUDE")

    def test_cloudflare_f1_ok(self):
        t = ("Do you now or in the future require immigration sponsorship to work for Cloudflare in the US? "
             "If you hold F1 status, please select YES and answer the next question about CPT or OPT.")
        cls, ev = K.classify(t)
        self.assertEqual(cls, "F1_OK")
        self.assertIn("F1", ev)

    def test_ibm_exclude(self):
        self.assertEqual(K.classify("IBM will not be providing visa sponsorship for this position now or in the future.")[0], "EXCLUDE")

    def test_intel_no_h1b(self):
        self.assertEqual(K.classify("Work model: hybrid. No H1B Sponsorship. Apply today.")[0], "NO_H1B_ONLY")
        self.assertEqual(K.classify("This role is not eligible for employment-based visa/immigration sponsorship.")[0], "NO_H1B_ONLY")

    def test_hard_excludes(self):
        for t in ("U.S. citizenship is required.", "Active security clearance needed.", "Subject to ITAR; U.S. person only."):
            self.assertEqual(K.classify(t)[0], "EXCLUDE", t)

    def test_silent_and_evidence_cap(self):
        self.assertEqual(K.classify("Build things with Linux and networks.")[0], "SILENT")
        cls, ev = K.classify("We will not sponsor " + "x" * 400 + " visas.")
        self.assertLessEqual(len(ev), 200)

    def test_sponsorship_available(self):
        self.assertEqual(K.classify("Visa sponsorship is available for this role.")[0], "F1_OK")
        self.assertNotEqual(K.classify("Visa sponsorship is not available.")[0], "F1_OK")


class Location(unittest.TestCase):
    def test_tiers(self):
        self.assertEqual(F.loc_tier("Austin, TX"), 1)
        self.assertEqual(F.loc_tier("Round Rock, TX, United States"), 1)
        self.assertEqual(F.loc_tier("Dallas, TX"), 2)
        self.assertEqual(F.loc_tier("Texas"), 2)
        self.assertEqual(F.loc_tier("Remote in USA"), 3)
        self.assertIsNone(F.loc_tier("Remote in Canada"))
        self.assertIsNone(F.loc_tier("London, UK"))
        self.assertIsNone(F.loc_tier("SF"))

    def test_best(self):
        self.assertEqual(F.best_location(["New York, NY", "Dallas, TX", "Austin, TX"]), (1, "Austin, TX"))
        self.assertEqual(F.best_location(["Paris, France"]), (None, ""))


class Filtering(unittest.TestCase):
    def ok(self, kind="newgrad", **kw):
        return F.simplify_ok(rec(**kw), kind, NOW)

    def test_basic(self):
        self.assertEqual(self.ok()[0], 1)
        self.assertIsNone(self.ok(active=False))
        self.assertIsNone(self.ok(title="Senior Software Engineer"))
        self.assertIsNone(self.ok(degrees=["PhD"]))
        self.assertIsNotNone(self.ok(degrees=[]))
        self.assertIsNone(self.ok(category="Quant"))
        self.assertIsNone(self.ok(date_posted=NOW - 400 * 86400))
        self.assertIsNone(self.ok(locations=["London, UK"]))

    def test_sponsorship(self):
        self.assertIsNone(self.ok(sponsorship="U.S. Citizenship is Required"))
        self.assertIsNone(self.ok("newgrad", sponsorship="Does Not Offer Sponsorship"))
        self.assertIsNotNone(self.ok("intern", sponsorship="Does Not Offer Sponsorship"))

    def test_boost_required_for_hardware(self):
        self.assertIsNone(self.ok(category="Hardware", title="Mechanical Engineer"))
        self.assertIsNotNone(self.ok(category="Hardware", title="Firmware Engineer"))

    def test_oracle_senior_exception(self):
        self.assertTrue(F.title_ok("Senior Data Center Support Services Technician"))
        self.assertFalse(F.title_ok("Senior Software Engineer"))


class StateAndPipeline(unittest.TestCase):
    def setUp(self):
        C.BASE_DIR = tempfile.mkdtemp()
        self.out = []
        self._orig = (net.http_json, net.http_get, report.add_backlog)
        net.http_json = self.fake_json
        net.http_get = lambda url, timeout=None: "<html></html>"
        report.add_backlog = lambda n, d: self.out.append(n) or True
        C.SIMPLIFY = [("newgrad", "NG"), ("intern", "IN")]
        C.ORACLE_KEYWORDS = []
        self.listings = {"NG": [rec(id="a"), rec(id="b", company_name="Bad", url="https://job-boards.greenhouse.io/bad/jobs/9")], "IN": []}
        self.texts = {"https://boards-api.greenhouse.io/v1/boards/bad/jobs/9?content=true&questions=true":
                      {"content": "We will not sponsor visas now or in the future."}}

    def tearDown(self):
        net.http_json, net.http_get, report.add_backlog = self._orig

    def fake_json(self, url, timeout=None):
        if url in self.listings:
            return self.listings[url]
        if url in self.texts:
            return self.texts[url]
        raise OSError("no network in test: " + url)

    def test_new_detection_and_exclude(self):
        now = dt.datetime(2026, 10, 14, 7, 0)
        cli.run(now=now)
        st = state.load()
        self.assertEqual(set(st["seen"]), {"simplify:a", "simplify:b"})
        self.assertEqual(st["seen"]["simplify:b"]["cls"], "EXCLUDE")
        md = open(report.report_path(now.date()), encoding="utf-8").read()
        self.assertIn("Acme", md)
        self.assertNotIn("Bad", md)
        self.assertIn("新着 1 件", md)
        self.assertEqual(self.out, [1])
        # 2回目は新着なし: 追記も backlog も増えない
        cli.run(now=now)
        self.assertEqual(self.out, [1])
        # 新規1件だけ拾う
        self.listings["NG"].append(rec(id="c", company_name="Newco"))
        cli.run(now=now)
        self.assertEqual(self.out, [1, 1])
        self.assertIn("Newco", open(report.report_path(now.date()), encoding="utf-8").read())

    def test_dry_run_writes_nothing(self):
        cli.run(dry=True, now=dt.datetime(2026, 10, 14, 7, 0))
        self.assertEqual(state.load()["seen"], {})
        self.assertEqual(self.out, [])

    def test_source_failure_is_isolated(self):
        del self.listings["IN"]  # intern 側は取得失敗
        cli.run(now=dt.datetime(2026, 10, 14, 7, 0))
        md = open(report.report_path(dt.date(2026, 10, 14)), encoding="utf-8").read()
        self.assertIn("取得失敗", md)
        self.assertIn("Acme", md)

    def test_fetch_cap_defers(self):
        C.MAX_FETCHES = 1
        state.save({"version": 1, "seen": {"x": {}}})  # 初回ではない
        cli.run(now=dt.datetime(2026, 10, 14, 7, 0))
        self.assertEqual(len(state.load()["seen"]), 2)  # x + 1件。残りは翌日
        C.MAX_FETCHES = 60


class Strip(unittest.TestCase):
    def test_strip_html(self):
        t = authcheck.strip_html("<p>No&nbsp;H1B</p><script>x()</script>")
        self.assertIn("No", t)
        self.assertNotIn("x()", t)


if __name__ == "__main__":
    unittest.main()
