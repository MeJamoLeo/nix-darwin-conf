import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from task_loop import completion_check as C  # noqa: E402


def iss(ident, desc, t="unstarted"):
    return {"identifier": ident, "title": "t " + ident, "description": desc, "state": {"name": "Todo", "type": t}}


class Ids(unittest.TestCase):
    def test_marker(self):
        self.assertEqual(C.assignment_id("source: x\nmarker: a:43147102\nraw: foo ⟨a:43147102⟩"), "43147102")

    def test_raw_only(self):
        self.assertEqual(C.assignment_id("raw: Quiz (due 11/3) ⟨a:43163386⟩"), "43163386")

    def test_new_format(self):
        self.assertEqual(C.assignment_id("Canvas assignment 43160364。期限なし"), "43160364")

    def test_page_marker_ignored(self):
        self.assertIsNone(C.assignment_id("marker: p:g0e8f00e5\nraw: 📄 Midterm ⟨p:g0e8f00e5⟩"))

    def test_none(self):
        self.assertIsNone(C.assignment_id(None))

    def test_parent_ref(self):
        self.assertEqual(C.parent_ref("説明\nparent: LIF-207\n続き"), "LIF-207")
        self.assertIsNone(C.parent_ref("この issue の parent: LIF-1 は本文中"))


class Classify(unittest.TestCase):
    def test_cases(self):
        c = C.classify
        self.assertEqual(c({"submitted_at": "2026-11-02T10:00:00Z", "workflow_state": "graded", "score": 18.0}), "submitted")
        self.assertEqual(c({"workflow_state": "pending_review"}), "submitted")
        self.assertEqual(c({"workflow_state": "submitted"}), "submitted")
        self.assertEqual(c({"workflow_state": "graded", "score": 10.0, "submitted_at": None}), "submitted")
        self.assertEqual(c({"workflow_state": "graded", "score": 0, "submitted_at": None}), "zero")
        self.assertEqual(c({"workflow_state": "graded", "score": 0, "submitted_at": "x"}), "submitted")
        self.assertEqual(c({"workflow_state": "graded", "score": None}), "none")
        self.assertEqual(c({"workflow_state": "unsubmitted", "score": None}), "none")
        self.assertEqual(c(None), "none")


class Plan(unittest.TestCase):
    def setUp(self):
        self.issues = [
            iss("LIF-1", "Canvas assignment 100"),
            iss("LIF-2", "parent: LIF-1"),
            iss("LIF-3", "parent: LIF-1", "completed"),
            iss("LIF-4", "marker: a:200"),
            iss("LIF-5", "marker: a:300"),
            iss("LIF-6", "marker: a:400", "completed"),
            iss("LIF-7", "parent: LIF-6"),
            iss("LIF-8", "marker: a:999"),
        ]
        sub = lambda **k: {"name": "n", "course": "c", "submission": k}  # noqa: E731
        self.asg = {
            "100": sub(workflow_state="graded", score=18.0, submitted_at="2026-11-02"),
            "200": sub(workflow_state="graded", score=0, submitted_at=None),
            "300": sub(workflow_state="unsubmitted"),
            "400": sub(workflow_state="graded", score=5, submitted_at="x"),
        }

    def test_children_lookup(self):
        _, kids = C.build_index(self.issues)
        self.assertEqual([k["identifier"] for k in kids["LIF-1"]], ["LIF-2", "LIF-3"])

    def test_plan(self):
        items, notes = C.plan(self.issues, self.asg)
        self.assertEqual([(i["parent"], i["to"], i["children"]) for i in items],
                         [("LIF-1", "Done", ["LIF-2"]), ("LIF-4", "Canceled", [])])
        self.assertTrue(any("LIF-8" in n and "999" in n for n in notes))
        self.assertTrue(any("LIF-7" in n and "LIF-6" in n for n in notes))

    def test_comment(self):
        items, _ = C.plan(self.issues, self.asg)
        self.assertIn("子 LIF-2 も Done", C.comment_body(items[0]))
        self.assertIn("0 点", C.comment_body(items[1]))



class DueInherit(unittest.TestCase):
    def _i(self, ident, due=None, parent=None, typ="unstarted"):
        return {"identifier": ident, "dueDate": due, "state": {"type": typ, "name": "Todo"},
                "description": f"parent: {parent}" if parent else "x"}

    def test_fills_only_empty_open_children(self):
        issues = [self._i("LIF-1", "2026-11-04"),
                  self._i("LIF-2", parent="LIF-1"),                    # 写す
                  self._i("LIF-3", "2026-11-02", parent="LIF-1"),      # 手で付けた期限は触らない
                  self._i("LIF-4", parent="LIF-1", typ="completed"),   # 閉じた子は触らない
                  self._i("LIF-5", parent="LIF-9"),                    # 親が一覧に無い
                  self._i("LIF-6"), self._i("LIF-7", parent="LIF-6")]  # 親に期限が無い
        self.assertEqual(C.plan_due_inherit(issues), [("LIF-2", "2026-11-04")])

if __name__ == "__main__":
    unittest.main()
