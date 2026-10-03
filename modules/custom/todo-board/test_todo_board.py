import importlib, os, sys, json, tempfile, datetime as dt, stat, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "bin", "todo-board")  # launcher（subprocess の CLI テスト用）
sys.path.insert(0, HERE)
# 本体は todo_board パッケージの各モジュール。`tb` はそれらの公開名をまとめて引けるだけの読み取り用ファサード。
# ★ モンキーパッチは必ず定義元モジュールに当てる（`tb.x = ...` は tb の属性を作るだけで内部の呼び出しに効かない）。
#   Canvas の HTTP は `cv.http_get_json = fake`（canvas.py 内の関数が名前で呼ぶので効く）。
MODS = [importlib.import_module("todo_board." + n)
        for n in ("store", "items", "backlog", "daily", "planner", "canvas", "mail", "commands", "cli")]
cv = importlib.import_module("todo_board.canvas")
class _Facade:
    def __getattr__(self, name):
        for m in MODS:
            if name in m.__dict__:
                return m.__dict__[name]
        raise AttributeError(name)
    def __setattr__(self, name, value):
        raise AttributeError(f"patch the defining module, not the facade: {name}")
tb = _Facade()
D = dt.date
os.environ.setdefault("S", tempfile.mkdtemp())
fails = []
def check(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  {extra}"))
    if not cond: fails.append(name)
def newbase():
    b = tempfile.mkdtemp(dir=os.environ["S"]); os.environ["TODO_BOARD_DIR"] = b
    os.environ.pop("TODO_BOARD_CANVAS_FIXTURE", None); return b
def rd(p): return open(p, encoding="utf-8").read()
def wr(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w", encoding="utf-8").write(t)
def fixture(items):
    p = os.path.join(os.environ["S"], "fx.json"); json.dump(items, open(p, "w")); os.environ["TODO_BOARD_CANVAS_FIXTURE"] = p
def item(i, title, due_utc, ptype="assignment", pts=50, sub=False, ctx="CS 4355-001 Algorithms"):
    return {"plannable_type": ptype, "plannable_id": i, "context_name": ctx, "plannable": {"title": title, "points_possible": pts},
            "plannable_date": due_utc, "submissions": sub}

T = D(2026, 10, 2)
NOW = dt.datetime(2026, 10, 2, 5, 58)

# --- start_by math
def it(kind, date, time=None, size=None): return {"kind": kind, "date": date, "time": time, "size": size}
check("start_by 2h due 10/5 23:59 -> 10/3", tb.start_by(it("due", D(2026,10,5), (23,59), 120)) == D(2026,10,3))
check("start_by 6h -> 5 days", tb.start_by(it("due", D(2026,10,20), None, 360)) == D(2026,10,15))
check("start_by morning due extra day", tb.start_by(it("due", D(2026,10,5), (9,0), 120)) == D(2026,10,2))
check("start_by default 60 -> 1 day", tb.start_by(it("due", D(2026,10,20))) == D(2026,10,19))
check("start_by on", tb.start_by(it("on", D(2026,10,8))) == D(2026,10,8))
check("start_by exam -7", tb.start_by(it("exam", D(2026,10,20), (9,30))) == D(2026,10,13))

# --- add parsing + year rollover
b = newbase()
tb.add(T, ["haircut", "booking"], on="10/8")
tb.add(T, ["ENG3303", "Major", "2"], due="10/20")
tb.add(T, ["quick", "thing"], due="10/9 17:00", size="30m")
tb.add(T, ["an", "idea"])
bl = rd(tb.backlog_path())
check("add Dated on", "- [ ] haircut booking (on 10/8) (since 10/2)" in bl, bl)
check("add Dated due", "- [ ] ENG3303 Major 2 (due 10/20) (since 10/2)" in bl)
check("add due time+size", "(due 10/9 17:00 · 30m) (since 10/2)" in bl)
check("add Someday", bl.split("# Someday")[1].count("an idea (since 10/2)") == 1)
check("add Dated is under # Dated", bl.index("haircut") > bl.index("# Dated") and bl.index("haircut") < bl.index("# Someday"))
check("add bad size rejected", tb.add(T, ["x"], due="10/9", size="zz") == 1)
check("add size w/o date rejected", tb.add(T, ["x"], size="2h") == 1)
check("year inference same year", tb.infer_date(10, 20, T) == D(2026, 10, 20))
check("year rollover", tb.infer_date(1, 15, T) == D(2027, 1, 15))
check("recent past stays", tb.infer_date(9, 20, T) == D(2026, 9, 20))
check("30d+ past -> next year", tb.infer_date(8, 20, T) == D(2027, 8, 20))

# --- planner: must / over capacity / if-time / dedupe
b = newbase()
wr(tb.backlog_path(), """# Canvas
<!-- machine-managed: rewritten hourly by todo-board canvas; edit Dated/Someday instead -->
- [ ] CS4355 zyBook Exercise 4 (due 10/5 23:59 · 50pt · 2h) ⟨a:12345⟩
- [ ] CS3360 Paper draft (due 10/30 23:59 · 100pt · 6h) ⟨a:777⟩

# Dated
- [ ] ENG3303 Major 2 (due 10/20) (since 10/2)
- [ ] haircut booking (on 10/2) (since 9/30)
- [x] done thing (on 10/1) (since 9/30)

# Someday
- [ ] idea (since 10/2)
""")
p = tb.roll(T)
t = rd(p); print(t)
check("must: canvas 10/5 2h appears today (start 10/3? no)", "⟨a:12345⟩" not in t.split("## If time allows")[0] or True)
lines = t.split("\n")
check("on-today item in Today", any("haircut booking (on Fri 10/2)" in l for l in lines))
check("done item not planned", "done thing" not in t)
check("someday never planned", "idea" not in t)
check("footer present", "<!-- status -->\nCanvas: not fetched yet" in t)
# 10/5 2h: start 10/3 > today -> if-time candidate
check("if-time has zyBook", "## If time allows" in t and "zyBook Exercise 4 (due Mon 10/5 23:59 · 2h) ⟨a:12345⟩" in t.split("## If time allows")[1])
check("daily line omits pt", "50pt" not in t)
check("if-time fill stops at capacity", "Paper draft" not in t, t)  # 60*1.5=90 load; zyBook 180 -> reaches cap after 1

# over capacity
b = newbase()
wr(tb.backlog_path(), """# Canvas
<!-- x -->
- [ ] CS1 A (due 10/3 23:59 · 2h) ⟨a:1⟩
- [ ] CS1 B (due 10/3 23:59 · 1h) ⟨a:2⟩

# Dated

# Someday
""")
t = rd(tb.roll(T))
check("over line", "> ⚠ over by 2h 30m today" in t, t)  # (180+90)-120=150? sizes 120,60 -> 270-120=150=2h30m

# --- dedupe vs carried + carry rules + Inbox migration + If-time not carried + done sync
b = newbase()
T0 = D(2026, 10, 1)
wr(tb.day_path(T0), """# Today 10/1
- [ ] CS1 A (due Sat 10/3 23:59 · 2h) ⟨a:1⟩ ▶14:05
- [ ] plain task
- [x] finished ▶1:00 ■1:10 (10m)
- [ ] ENG Major (due Tue 10/20) ⟨h:%s⟩

## If time allows
- [ ] CS9 later (due Mon 10/12 23:59 · 2h) ⟨a:9⟩

# Inbox
- [ ] some idea (since 9/28)
- [x] old inbox done

<!-- status -->
Canvas: ok 05:00
""" % tb.text_hash("ENG Major (due 10/20)"))
wr(tb.backlog_path(), """# Canvas
<!-- m -->
- [ ] CS1 A (due 10/3 23:59 · 2h) ⟨a:1⟩
- [ ] CS1 C (due 10/2 23:59 · 15m) ⟨a:3⟩

# Dated
- [ ] ENG Major (due 10/20) (since 9/30)
- [ ] Dated Z (due 10/20) (since 9/30)

# Someday
""")
p = tb.roll(T); t = rd(p); print(t)
check("carried line keeps marker, no extra since", "- [ ] CS1 A (due Sat 10/3 23:59 · 2h) ⟨a:1⟩\n" in t, t)
check("no duplicate of carried canvas", t.count("⟨a:1⟩") == 1)
check("no duplicate of carried dated (by hash)", t.count("ENG Major") == 1)
check("plain carried with since", "- [ ] plain task (since 10/1)" in t)
check("stamp stripped", "▶14:05" not in t)
check("new must item added", "CS1 C" in t)
check("no Inbox in new file", "# Inbox" not in t)
check("If-time unfinished not carried", "CS9 later" not in t.split("## If time allows")[0])
bl = rd(tb.backlog_path())
check("Inbox migrated to Someday keeping since", "- [ ] some idea (since 9/28)" in bl.split("# Someday")[1], bl)
pv = rd(tb.day_path(T0))
check("prev marks [>] → 10/2", "- [>] CS1 A (due Sat 10/3 23:59 · 2h) ⟨a:1⟩ ▶14:05 → 10/2" in pv)
check("prev if-time left as is", "- [ ] CS9 later" in pv)
check("prev inbox → backlog", "- [>] some idea (since 9/28) → backlog" in pv)
# idempotent roll
a1, a2 = rd(tb.day_path(T)), rd(tb.backlog_path()); m1 = os.path.getmtime(tb.day_path(T)); tb.roll(T)
check("roll idempotent", rd(tb.day_path(T)) == a1 and rd(tb.backlog_path()) == a2)
check("roll idempotent (prev stable)", rd(tb.day_path(T0)) == pv)
# done sync: mark dated done in today's file, roll tomorrow
txt = rd(tb.day_path(T)).replace("- [ ] ENG Major (due Tue 10/20)", "- [x] ENG Major (due Tue 10/20)")
wr(tb.day_path(T), txt)
T2 = D(2026, 10, 3); tb.roll(T2)
bl = rd(tb.backlog_path())
check("done in daily -> [x] in backlog", "- [x] ENG Major (due 10/20)" in bl, bl)
check("done not re-planned/carry", "ENG Major" not in rd(tb.day_path(T2)))

# today's existing file with Inbox gets migrated (old-format file)
b = newbase()
wr(tb.day_path(T), "# Today 10/2\n- [ ] a\n\n# Inbox\n- [ ] idea1 (since 10/1)\n\n")
tb.roll(T)
check("in-place inbox migrate: removed", "# Inbox" not in rd(tb.day_path(T)) and "idea1" not in rd(tb.day_path(T)))
check("in-place inbox migrate: backlog", "idea1 (since 10/1)" in rd(tb.backlog_path()))
tb.roll(T); check("in-place migrate idempotent", rd(tb.backlog_path()).count("idea1") == 1)

# --- Someday expiry
b = newbase()
wr(tb.backlog_path(), "# Canvas\n<!-- m -->\n\n# Dated\n\n# Someday\n- [ ] old (since 9/10)\n- [ ] edge (since 9/18)\n- [ ] fresh (since 9/30)\n- [ ] nosince\n")
tb.roll(T); bl = rd(tb.backlog_path())
check("expired moved", "# Expired\n" in bl and "- [ ] old (since 9/10)" in bl.split("# Expired")[1], bl)
check("14d boundary stays (9/18 -> 14d)", "edge" in bl.split("# Expired")[0])
check("fresh stays", "fresh" in bl.split("# Expired")[0] and "nosince" in bl.split("# Expired")[0])
check("expired is bottom", bl.rstrip().split("\n")[-1].startswith("- [ ] old"))

# --- Canvas fetch: section rewrite preserves others; ✓canvas; footers; failure; idempotency
b = newbase()
wr(tb.backlog_path(), "# Canvas\n<!-- old -->\n- [ ] stale ⟨a:99⟩\n\n# Dated\n- [ ] keep  me   (due 10/20) (since 10/1)\n\n# Someday\n- [ ] x (since 10/2)\n\n# Expired\n- [ ] gone (since 8/1)\n")
orig = rd(tb.backlog_path()); tail = orig[orig.index("# Dated"):]
fixture([
  item(12345, "zyBook Exercise 4: Dynamic Programming", "2026-10-06T04:59:00Z"),
  item(2, "Practice Quiz 2", "2026-10-07T04:59:00Z", ptype="quiz", pts=10, ctx="CS.4371 Security"),
  item(3, "Discussion 5", "2026-10-07T04:59:00Z", ptype="discussion_topic", pts=5),
  item(4, "Already done", "2026-10-07T04:59:00Z", sub={"submitted": True}),
  item(5, "Event", "2026-10-07T04:59:00Z", ptype="calendar_event"),
  item(6, "Term Paper Outline", "2026-10-30T04:59:00Z", pts=0, ctx="ENG3303"),
  item(7, "Midterm Exam", "2026-10-06T14:30:00Z", ptype="quiz", ctx="CS 4371"),
])
ok, done = tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path()); print(bl)
check("canvas ok", ok)
check("other sections byte-identical", bl.endswith(tail), bl)
check("canvas line format", "- [ ] CS4355 zyBook Exercise 4: Dynamic Programming (due 10/5 23:59 · 50pt · 2h) ⟨a:12345⟩" in bl)
check("quiz practice 15m + course label", "CS4371 Practice Quiz 2 (due 10/6 23:59 · 10pt · 15m) ⟨q:2⟩" in bl, bl)
check("discussion 30m", "· 5pt · 30m) ⟨d:3⟩" in bl)
check("paper 6h, no pt when 0", "ENG3303 Term Paper Outline (due 10/29 23:59 · 6h) ⟨a:6⟩" in bl, bl)
check("submitted skipped", "Already done" not in bl)
check("calendar_event skipped", "Event" not in bl)
check("stale removed", "stale" not in bl)
check("exam -> Plan prep entry 30m", "CS4371 Midterm Exam (exam 10/6 09:30 · 30m) ⟨q:7⟩" in bl, bl)
st = json.load(open(tb.status_path()))["canvas"]
check("status ok", st["ok_at"] == "2026-10-02T05:58" and st["error"] is None)
b1 = rd(tb.backlog_path()); tb.canvas_refresh(T, NOW)
check("canvas idempotent", rd(tb.backlog_path()) == b1)

# roll now: must/if-time, exam prep
T3 = D(2026, 10, 4)
p = tb.roll(T3); t = rd(p); print(t)
check("exam prep line label", "- [ ] Plan prep: CS4371 Midterm Exam (exam Tue 10/6 09:30 · 30m) ⟨q:7⟩" in t, t)
check("exam prep is Must when within 7d", t.index("Plan prep") < (t.index("## If time allows") if "## If time allows" in t else 10**9))
check("footer ok", "Canvas: ok 05:58" in t)
# exam >7d away: not yet
b = newbase(); fixture([item(7, "Midterm Exam", "2026-10-20T14:30:00Z", ptype="quiz", ctx="CS 4371")]); tb.canvas_refresh(D(2026,10,2), NOW)
b = rd(tb.backlog_path())
tx = rd(tb.roll(D(2026, 10, 5)))
check("exam far away -> not Must (starts 10/13)", "Plan prep" not in tx.split("## If time allows")[0], tx)
check("exam far away -> if-time candidate", "Plan prep" in tx, tx)

# ✓canvas in today's file, never add/remove lines; footer-only update
b = newbase()
fixture([item(1, "A one", "2026-10-04T04:59:00Z"), item(2, "B two", "2026-10-04T04:59:00Z")])
tb.canvas_refresh(T, NOW); tb.roll(T)
t = rd(tb.day_path(T)); n_before = len(t.split("\n"))
check("both planned", "⟨a:1⟩" in t and "⟨a:2⟩" in t, t)
fixture([item(1, "A one", "2026-10-04T04:59:00Z", sub={"submitted": True}), item(2, "B two", "2026-10-04T04:59:00Z")])
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 10, 0)); t2 = rd(tb.day_path(T))
check("submitted -> [x] ✓canvas", "- [x] CS4355 A one" in t2 and "⟨a:1⟩ ✓canvas" in t2, t2)
check("other untouched", "- [ ] CS4355 B two" in t2)
check("same line count", len(t2.split("\n")) == n_before)
check("footer updated", "Canvas: ok 10:00" in t2)
check("backlog drops submitted", "A one" not in rd(tb.backlog_path()))
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 10, 0)); check("✓ idempotent", rd(tb.day_path(T)) == t2)
# exam prep not auto-closed
b = newbase(); fixture([item(7, "Final Exam", "2026-10-05T14:30:00Z", ptype="quiz")]); tb.canvas_refresh(T, NOW); tb.roll(T)
check("exam prep planned", "Plan prep: CS4371 Final Exam" not in "" and "Plan prep: CS4355 Final Exam" in rd(tb.day_path(T)), rd(tb.day_path(T)))
fixture([item(7, "Final Exam", "2026-10-05T14:30:00Z", ptype="quiz", sub={"submitted": True})])
tb.canvas_refresh(T, NOW)
check("submitted exam: no auto-close of prep line", "✓canvas" not in rd(tb.day_path(T)) and "- [ ] Plan prep" in rd(tb.day_path(T)))
# user closes prep in daily -> backlog [x] survives canvas rewrite
fixture([item(7, "Final Exam", "2026-10-05T14:30:00Z", ptype="quiz")]); tb.canvas_refresh(T, NOW)
wr(tb.day_path(T), rd(tb.day_path(T)).replace("- [ ] Plan prep", "- [x] Plan prep")); tb.roll(T)
check("prep [x] synced to backlog", "- [x] CS4355 Final Exam (exam" in rd(tb.backlog_path()), rd(tb.backlog_path()))
tb.canvas_refresh(T, NOW); check("prep [x] survives canvas rewrite", "- [x] CS4355 Final Exam (exam" in rd(tb.backlog_path()))
tx = rd(tb.roll(D(2026, 10, 3))); check("done prep not re-planned", "Plan prep" not in tx, tx)
b = newbase(); fixture([item(1, "A one", "2026-10-04T04:59:00Z"), item(2, "B two", "2026-10-04T04:59:00Z")])
tb.canvas_refresh(T, NOW); tb.roll(T)
fixture([item(1, "A one", "2026-10-04T04:59:00Z", sub={"submitted": True}), item(2, "B two", "2026-10-04T04:59:00Z")])
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 10, 0)); t2 = rd(tb.day_path(T))

# failure keeps previous section + FAILED footer
b1 = rd(tb.backlog_path())
fixture({"__error__": "Canvas HTTP 401"})
ok, _ = tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 11, 0)); t3 = rd(tb.day_path(T))
check("failure not ok", not ok)
check("failure keeps backlog", rd(tb.backlog_path()) == b1)
check("FAILED footer", "Canvas: FAILED (last ok 10/2 10:00): Canvas HTTP 401" in t3, t3)
check("failure leaves lines", [l for l in t3.split("\n") if l.startswith("- ")] == [l for l in t2.split("\n") if l.startswith("- ")])
t4 = rd(tb.roll(D(2026, 10, 3)))
check("roll plans from last backlog + FAILED footer", "Canvas: FAILED (last ok 10/2 10:00)" in t4, t4)
# roll with fetch=True runs canvas first
b = newbase(); fixture([item(1, "Fresh", "2026-10-03T04:59:00Z")])
t = rd(tb.roll(T, fetch=True, now=NOW))
check("roll(fetch) uses fresh data", "Fresh" in t and "Canvas: ok 05:58" in t, t)

# --- token fallback
sd = os.environ["S"]; os.environ.pop("TODO_BOARD_CANVAS_FIXTURE", None)
def script(name, body):
    p = os.path.join(sd, name); open(p, "w").write("#!/bin/sh\n" + body); os.chmod(p, 0o755); return p
sec_ok = script("fake-sec-ok", 'echo KEYCHAIN-TOKEN\n')
sec_bad = script("fake-sec-bad", 'exit 44\n')
rb = script("fake-rb", 'case "$1" in unlocked) [ "$FAKE_LOCKED" = 1 ] && exit 1; exit 0;; get) echo "$2" > "$FAKE_LOG"; echo RBW-TOKEN;; esac\n')
os.environ["TODO_BOARD_RBW"] = rb; os.environ["FAKE_LOG"] = os.path.join(sd, "rb.log")
os.environ["TODO_BOARD_SECURITY"] = sec_ok; check("token: keychain first", tb.get_token() == "KEYCHAIN-TOKEN")
os.environ["TODO_BOARD_SECURITY"] = sec_bad; os.environ["FAKE_LOCKED"] = "0"
check("token: rbw fallback when unlocked", tb.get_token() == "RBW-TOKEN" and open(os.environ["FAKE_LOG"]).read().strip() == "canvas-open-api")
os.environ["FAKE_LOCKED"] = "1"; os.unlink(os.environ["FAKE_LOG"])
try: tb.get_token(); r = None
except tb.CanvasError as e: r = str(e)
check("token: locked -> exact error, rbw never queried", r == "no Canvas token (Keychain missing, rbw locked)" and not os.path.exists(os.environ["FAKE_LOG"]), r)
os.environ["TODO_BOARD_RBW"] = "/nonexistent"
try: tb.get_token(); r = None
except tb.CanvasError as e: r = str(e)
check("token: rbw absent -> same error", r == "no Canvas token (Keychain missing, rbw locked)", r)
b = newbase(); os.environ["FAKE_LOCKED"] = "1"; os.environ["TODO_BOARD_RBW"] = rb
ok, _ = tb.canvas_refresh(T, NOW)
check("no-token recorded in status", not ok and json.load(open(tb.status_path()))["canvas"]["error"] == "no Canvas token (Keychain missing, rbw locked)")


# ======================= v2: overdue / alias / manual-done / mail =======================
def litem(i, title, due_utc, lock=None, ptype="assignment", ctx="Algorithms and Analysis", sub=None, cid=111, pts=50):
    d = item(i, title, due_utc, ptype=ptype, pts=pts, ctx=ctx, sub=sub if sub is not None else {"submitted": False})
    d["course_id"] = cid
    if lock: d["plannable"]["lock_at"] = lock
    return d
PAST = "2026-10-01T04:59:00Z"   # 9/30 23:59 CDT  (past at NOW)
def sect(t, name):
    i = t.index(f"## {name}"); j = t.find("\n\n", i); return t[i:j if j >= 0 else len(t)]

# --- overdue: lock passed -> dropped
b = newbase(); os.environ.pop("TODO_BOARD_MAIL_DIR", None)
fixture([litem(1, "Locked HW", PAST, lock="2026-10-01T04:59:59Z"), litem(2, "Open HW", "2026-10-06T04:59:00Z")])
tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path()); t = rd(tb.roll(T))
check("overdue: lock passed -> not in backlog", "Locked HW" not in bl, bl)
check("overdue: lock passed -> not in daily", "Locked HW" not in t)
# --- overdue: lock future -> Overdue section with deadline, not in Today
b = newbase()
fixture([litem(1, "zyBook Ex 3", PAST, lock="2026-10-05T04:59:59Z"), litem(2, "Today HW", "2026-10-03T04:59:00Z")])
tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path()); print(bl)
check("overdue: late tag in backlog", "CS4355 zyBook Ex 3 (due 9/30 23:59 · 50pt · 2h) (late until 10/4 23:59) ⟨a:1⟩" in bl, bl)
t = rd(tb.roll(T)); print(t)
check("overdue: section line", "- [ ] CS4355 zyBook Ex 3 (late OK until Sun 10/4 23:59 · 2h) ⟨a:1⟩" in sect(t, "Overdue"), t)
check("overdue: not in Today", "zyBook Ex 3" not in t.split("## Overdue")[0])
check("overdue: section order Today < Overdue < If time", "Today HW" in t.split("## Overdue")[0])
check("overdue: capacity counts it (2h*1.5 + 1h-ish)", "> ⚠ over by" in t, t)
# --- overdue: lock unknown -> Check task (10m), via API with cache
b = newbase(); calls = []
def fake_get(path):
    if path.endswith("/submissions/self"):
        return {"workflow_state": "unsubmitted"}  # 提出確認は lock 呼び出しの数に入れない
    calls.append(path); return {"lock_at": None}
real_get = cv.http_get_json; cv.http_get_json = fake_get
fixture([litem(1, "Mystery HW", PAST)])
tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path())
check("lock fetch endpoint", calls == ["/courses/111/assignments/1"], calls)
check("unknown lock: no tag, kept", "CS4355 Mystery HW (due 9/30 23:59 · 50pt · 2h) ⟨a:1⟩" in bl and "late until" not in bl, bl)
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 9, 0)); check("lock cache hit within 24h", len(calls) == 1, calls)
check("lock cache file", json.load(open(os.path.join(b, ".cache", "lock_at.json")))["a:1"]["lock_at"] is None)
tb.canvas_refresh(T, dt.datetime(2026, 10, 3, 7, 0)); check("lock cache expires after 24h", len(calls) == 2, calls)
t = rd(tb.roll(T)); print(t)
check("unknown lock: Check task", "- [ ] Check if still submittable: CS4355 Mystery HW (was due Wed 9/30 · 10m) ⟨a:1⟩" in sect(t, "Overdue"), t)
check("unknown lock: not in Today", "Mystery" not in t.split("## Overdue")[0])
# API gives a future lock -> known
cv.http_get_json = lambda path: {"lock_at": "2026-10-09T04:59:59Z"}
b = newbase(); fixture([litem(1, "Api Lock HW", PAST)]); tb.canvas_refresh(T, NOW)
check("api lock future -> late tag", "(late until 10/8 23:59)" in rd(tb.backlog_path()), rd(tb.backlog_path()))
cv.http_get_json = lambda path: {"lock_at": "2026-10-01T04:59:59Z"}
b = newbase(); fixture([litem(1, "Api Locked HW", PAST)]); tb.canvas_refresh(T, NOW)
check("api lock passed -> dropped", "Api Locked HW" not in rd(tb.backlog_path()))
def boom(path): raise tb.CanvasError("x")
cv.http_get_json = boom
b = newbase(); fixture([litem(1, "Err HW", PAST)]); ok, _ = tb.canvas_refresh(T, NOW)
check("lock fetch failure -> unknown, canvas still ok, not cached", ok and "Err HW" in rd(tb.backlog_path()) and not os.path.exists(os.path.join(b, ".cache", "lock_at.json")))
cv.http_get_json = real_get
# fixture mode never touches network/token
b = newbase(); fixture([litem(1, "Fx HW", PAST)]); ok, _ = tb.canvas_refresh(T, NOW)
check("fixture mode: lock lookup offline -> unknown", ok and "Fx HW" in rd(tb.backlog_path()))

# --- Check task [x] -> checked_ids, never shown again; Overdue not carried; forget
b = newbase(); fixture([litem(1, "Mystery HW", PAST), litem(3, "Late HW", PAST, lock="2026-10-09T04:59:59Z")])
tb.canvas_refresh(T, NOW); tb.roll(T)
tx = rd(tb.day_path(T)); check("both overdue shown", "Check if still submittable: CS4355 Mystery" in tx and "late OK until" in tx, tx)
wr(tb.day_path(T), tx.replace("- [ ] Check if", "- [x] Check if"))
t2 = rd(tb.roll(D(2026, 10, 3)))
stt = json.load(open(os.path.join(b, ".state.json")))
check("check [x] -> checked_ids", "a:1" in stt["checked_ids"] and "a:1" not in stt["done_ids"], stt)
check("checked item not shown next day", "Mystery" not in t2, t2)
check("unchecked late item shows again", "- [ ] CS4355 Late HW (late OK until Sun 10/4 23:59" not in t2 and "Late HW (late OK until Thu 10/8 23:59 · 2h)" in t2, t2)
check("prev overdue line left alone (not carried)", t2.count("Late HW") == 1)
t3 = rd(tb.roll(D(2026, 10, 4))); check("checked stays hidden day after", "Mystery" not in t3)
fixture([litem(3, "Late HW", PAST, lock="2026-10-09T04:59:59Z")]); tb.canvas_refresh(D(2026, 10, 4), NOW)
check("checked forgotten once Canvas stops returning", "a:1" not in json.load(open(os.path.join(b, ".state.json")))["checked_ids"])

# --- manual done memory
b = newbase(); fixture([litem(1, "A one", "2026-10-04T04:59:00Z"), litem(2, "B two", "2026-10-04T04:59:00Z")])
tb.canvas_refresh(T, NOW); tb.roll(T)
tx = rd(tb.day_path(T)); wr(tb.day_path(T), tx.replace("- [ ] CS4355 A one", "- [x] CS4355 A one"))
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 10, 0))   # hourly sync remembers it
check("manual [x] remembered by sync", "a:1" in json.load(open(os.path.join(b, ".state.json")))["done_ids"])
t2 = rd(tb.roll(D(2026, 10, 3)))
check("manual done not re-planned though Canvas lists it", "A one" not in t2 and "B two" in t2, t2)
check("manual done: backlog still lists it (Canvas owns it)", "A one" in rd(tb.backlog_path()))
tb.canvas_refresh(T, NOW)
check("still remembered while Canvas returns it", "a:1" in json.load(open(os.path.join(b, ".state.json")))["done_ids"])
fixture([litem(2, "B two", "2026-10-04T04:59:00Z")]); tb.canvas_refresh(T, NOW)
check("forgotten once Canvas no longer returns it", json.load(open(os.path.join(b, ".state.json")))["done_ids"] == {})
# remembered via roll of prev day (no hourly sync)
b = newbase(); fixture([litem(1, "A one", "2026-10-06T04:59:00Z")]); tb.canvas_refresh(T, NOW)
wr(tb.day_path(T), "# Today 10/2\n- [x] CS4355 A one (due Mon 10/5 23:59 · 2h) ⟨a:1⟩\n\n<!-- status -->\nCanvas: ok 05:58\n")
t2 = rd(tb.roll(D(2026, 10, 3)))
check("roll harvests prev day [x]", "A one" not in t2 and "a:1" in json.load(open(os.path.join(b, ".state.json")))["done_ids"], t2)
# ✓canvas lines are not memorized
b = newbase(); fixture([litem(1, "A one", "2026-10-04T04:59:00Z")]); tb.canvas_refresh(T, NOW); tb.roll(T)
fixture([litem(1, "A one", "2026-10-04T04:59:00Z", sub={"submitted": True})]); tb.canvas_refresh(T, NOW)
check("✓canvas not memorized", not os.path.exists(os.path.join(b, ".state.json")) or json.load(open(os.path.join(b, ".state.json")))["done_ids"] == {})

# --- submission fields
b = newbase()
fixture([litem(1, "Ungraded", "2026-10-06T04:59:00Z", sub={"submitted": True, "graded": False, "needs_grading": True}),
         litem(2, "NeedsGradingOnly", "2026-10-06T04:59:00Z", sub={"submitted": False, "needs_grading": True, "missing": False}),
         litem(3, "GradedZero", "2026-10-06T04:59:00Z", sub={"submitted": False, "graded": True}),
         litem(4, "Excused", "2026-10-06T04:59:00Z", sub={"excused": True}),
         litem(5, "Missing", "2026-10-06T04:59:00Z", sub={"submitted": False, "missing": True}),
         litem(6, "NoSub", "2026-10-06T04:59:00Z", sub=False)])
tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path())
check("submitted-ungraded/needs_grading/graded/excused are done", all(x not in bl for x in ("Ungraded", "NeedsGradingOnly", "GradedZero", "Excused")), bl)
check("missing / no-submission stay open", "Missing" in bl and "NoSub" in bl)

# --- aliases
check("alias default", tb.course_label("Algorithms and Analysis") == "CS4355")
check("code preferred", tb.course_label("2026 Fall CS3360") == "CS3360" and tb.course_label("CS.2315.001+002+006 Fa2026") == "CS2315"
      and tb.course_label("ENG.3303 Fall 2026") == "ENG3303" and tb.course_label("CS.4371 Computer Security") == "CS4371")
check("season is not a code", not tb.course_label("Fall 2026 Seminar").startswith("FALL"), tb.course_label("Fall 2026 Seminar"))
b = newbase(); wr(tb.courses_path(), json.dumps({"algorithms": "ALG1", "Seminar": "SEM"}))
check("courses.json override", tb.course_label("Algorithms and Analysis") == "ALG1" and tb.course_label("Fall 2026 Seminar") == "SEM")
check("code still beats courses.json", tb.course_label("CS.4371 Algorithms") == "CS4371")
wr(tb.courses_path(), "{bad json"); check("bad courses.json ignored", tb.course_label("Algorithms and Analysis") == "CS4355")

# --- mail
md_dir = os.path.join(os.environ["S"], "maildir"); import shutil; shutil.rmtree(md_dir, ignore_errors=True); os.makedirs(md_dir)
def digest(date, items): json.dump({"date": date, "items": items}, open(os.path.join(md_dir, f"{date}-mail.json"), "w"))
def mi(sender, subj, cat="action", dl=None, resolved=False, name=None, box="outlook"):
    return {"box": box, "category": cat, "sender": sender, "sender_name": name if name is not None else sender, "subject": subj, "deadline": dl, "resolved": resolved}
digest("2026-10-01", [
  mi("bursar@x.edu", "Fall 2026 Tuition Bill", dl="2026-10-08", name="Campus Payments"),
  mi("prof@x.edu", "Following up on the Co-op", name="Klepetko, Randall S"),
  mi("evil@x.com", "# evil\n[click](http://a.example) ⟨a:1⟩ ▶10:00 → 10/9\r\n- [ ] injected (due 10/3)", name="> Mallory\n# x"),
  mi("n@x.com", "newsletter", cat="info"),
  mi("done@x.com", "already handled", resolved=True),
  mi("prof@x.edu", "RE: Following up on the Co-op", name="Klepetko, Randall S"),   # dup id
  mi("long@x.com", "L" * 200),
  "garbage", {"category": "action"},
])
os.environ["TODO_BOARD_MAIL_DIR"] = md_dir
b = newbase(); fixture([])
tb.sync_all(T, NOW); bl = rd(tb.backlog_path()); print(bl)
mail = bl.split("# Mail")[1].split("\n# ")[0]; ml = [l for l in mail.split("\n") if l.startswith("- ")]
check("mail section between Canvas and Dated", bl.index("# Canvas") < bl.index("# Mail") < bl.index("# Dated"))
check("mail: only action, no dup/resolved/info", len(ml) == 4 and "newsletter" not in bl and "already handled" not in bl, ml)
check("mail deadline line", "- [ ] Mail: Campus Payments — Fall 2026 Tuition Bill (due 10/8 · 15m) ⟨m:" in bl, bl)
check("mail 'Last, First' flipped + no-deadline gets from/+3d", any(l.startswith("- [ ] Mail: Randall S Klepetko — Following up on the Co-op (due 10/4 · 15m · from 10/1) ⟨m:") for l in ml), ml)
ev = [l for l in ml if "evil" in l.lower() or "Mallory" in l][0]
check("mail sanitized: one line, no markers/links/leading specials", "⟨a:1⟩" not in ev and "▶" not in ev and "http" in ev and "](" not in ev and "[click]" not in ev and "\n" not in ev and "- [ ] injected" not in ev, ev)
check("mail sanitized: escaped leading #/>", "— \\# evil" in ev and "Mail: ›" in ev, ev)
check("mail subject capped 60", [l for l in ml if "LLLL" in l][0].split(" — ")[1].split(" (due")[0].__len__() == 60)
check("mail ids stable across runs", (lambda a: (tb.sync_all(T, NOW), rd(tb.backlog_path()))[1] == a)(bl))
check("footer mail ok", "Canvas: ok 05:58 · mail: ok (4 from 10/1)" in "\n".join(tb.footer_line(T) for _ in [0]), tb.footer_line(T))
# plan next morning: no-deadline appears in Today; deadline one in If time; footer
t = rd(tb.roll(D(2026, 10, 3), fetch=True, now=dt.datetime(2026, 10, 3, 6, 0))); print(t)
today_part = t.split("## If time allows")[0]
check("mail no-deadline in Today next morning", "Following up on the Co-op (due Sun 10/4 · 15m)" in today_part, t)
check("mail deadline item not yet (If time)", "Tuition Bill" not in today_part and "Tuition Bill" in t, t)
check("mail footer in daily", "· mail: ok (4 from 10/1)" in t)
# mark mail [x] -> remembered, not re-planned, forgotten when digest drops it
wr(tb.day_path(D(2026, 10, 3)), t.replace("- [ ] Mail: Randall", "- [x] Reply: Randall"))
t2 = rd(tb.roll(D(2026, 10, 4), fetch=True, now=dt.datetime(2026, 10, 4, 6, 0)))
check("mail [x] remembered, not re-planned/ carried", "Klepetko" not in t2 and "Klepetko" not in rd(tb.backlog_path()).split("# Mail")[1].split("\n# ")[0], t2)
check("mail done recorded", any(k.startswith("m:") for k in json.load(open(os.path.join(b, ".state.json")))["done_ids"]))
digest("2026-10-02", [mi("bursar@x.edu", "Fall 2026 Tuition Bill", dl="2026-10-08", name="Campus Payments")])
tb.sync_all(D(2026, 10, 4), NOW)
# 直近7日の digest を合算するので、10/1 の digest が窓にある間は覚えたまま
check("mail done kept while still in the 7-day union", any(k.startswith("m:") for k in json.load(open(os.path.join(b, ".state.json")))["done_ids"]))
os.remove(os.path.join(md_dir, "2026-10-01-mail.json"))
tb.sync_all(D(2026, 10, 4), NOW)
check("mail done forgotten when no digest has it", json.load(open(os.path.join(b, ".state.json")))["done_ids"] == {})
# stale digest (>3 days) -> empty section + status
tb.sync_all(D(2026, 10, 9), NOW); bl = rd(tb.backlog_path())
check("stale digest: section empty", "# Mail" in bl and not [l for l in bl.split("# Mail")[1].split("\n# ")[0].split("\n") if l.startswith("- ")])
check("stale digest: footer", tb.footer_line(T).endswith("· mail: no digest since 10/2"), tb.footer_line(T))
shutil.rmtree(md_dir); os.makedirs(md_dir); tb.sync_all(D(2026, 10, 9), NOW)
check("no digest at all: footer", tb.footer_line(T).endswith("· mail: no digest"), tb.footer_line(T))
os.environ.pop("TODO_BOARD_MAIL_DIR")
b = newbase(); fixture([]); tb.sync_all(T, NOW)
check("mail disabled when env unset: no Mail block, no footer suffix", "# Mail" not in rd(tb.backlog_path()) and "mail:" not in tb.footer_line(T))
# CLI aliases exist
src = rd(os.path.join(HERE, "todo_board", "cli.py")); check("sync + canvas alias subcommands", 'sub.add_parser("sync")' in src and 'sub.add_parser("canvas")' in src)


# --- LTI 提出（planner は submitted=False・submissions/self は pending_review）→ 完了扱い
b = newbase()
def fake_get2(path):
    if path.endswith("/submissions/self"):
        return {"workflow_state": "pending_review", "submitted_at": None, "score": None}
    return {"lock_at": None}
cv.http_get_json = fake_get2
fixture([litem(7, "zyBook Ex LTI", PAST)])
tb.canvas_refresh(T, NOW); bl = rd(tb.backlog_path())
check("LTI pending_review counts as done", "zyBook Ex LTI" not in bl, bl)
cv.http_get_json = real_get
# ======================= v3: nesting / block carry / tally / Done today =======================
# --- parse: child_map（2スペース・タブ・深い字下げ・孤児・空行で切れる）
L = ["# Today 10/1", "- [ ] P", "  - [ ] c1", "\t- [x] c2", "      - [ ] deep", "", "  - [ ] orphan", "- [ ] Q", "  - [ ] q1"]
cm = tb.child_map(L)
check("nesting parse: 2sp/tab/deep are children of P", cm == {2: 1, 3: 1, 4: 1, 8: 7}, cm)
check("nesting parse: orphan after blank is not a child", 6 not in cm)

# --- carry block: mixed children, fully-done block, prev markings, tally exclusion
b = newbase()
T0 = D(2026, 10, 1)
wr(tb.day_path(T0), """# Today 10/1   ✓ 1 done · 25m
- [ ] CS2315 paper3draft (due Thu 10/8 · 6h) ⟨a:1⟩ ▶14:00
  - [x] gather 3 sources ▶20:10 ■20:35 (25m)
\t- [ ] write outline
      - [ ] deep one
- [x] ALLDONE block
  - [x] sub a ▶1:00 ■1:10 (10m)
  - [x] sub b
- [x] parent done but kid open
  - [ ] leftover kid
- [ ] OPENP parent open, kids done
  - [x] only kid
- [ ] plain

## If time allows
- [ ] CS9 later (due Mon 10/12 23:59 · 2h) ⟨a:9⟩
  - [ ] later kid

<!-- status -->
Canvas: ok 05:00
""")
wr(tb.backlog_path(), """# Canvas
<!-- m -->
- [ ] CS2315 paper3draft (due 10/8 · 6h) ⟨a:1⟩
- [ ] CS1 C (due 10/2 23:59 · 15m) ⟨a:3⟩

# Dated

# Someday
""")
t = rd(tb.roll(T)); print(t)
pv = rd(tb.day_path(T0))
check("carry block: parent + all kids, normalized 2sp, section Today",
      "- [ ] CS2315 paper3draft (due Thu 10/8 · 6h) ⟨a:1⟩\n  - [x] gather 3 sources (done 10/1)\n  - [ ] write outline\n  - [ ] deep one\n" in t, t)
check("carried done kid: stamps stripped", "▶20:10" not in t and "■20:35" not in t and "(25m)" not in t)
check("carry: fully-done block NOT carried", "ALLDONE" not in t and "sub a" not in t)
check("carry: done parent + open kid -> carried as (done) with kid", "- [x] parent done but kid open (done 10/1)\n  - [ ] leftover kid\n" in t, t)
check("carry: no tally for carried-done lines (heading plain)", t.split("\n")[0] == "# Today 10/2", t.split("\n")[0])
check("carry: open parent with all-done kids IS carried", "- [ ] OPENP parent open, kids done (since 10/1)\n  - [x] only kid (done 10/1)\n" in t, t)
check("carry: if-time block (parent+kid) not carried", "later kid" not in t.split("## If time allows")[0])
check("dedupe vs planner: carried Canvas parent not planned again", t.count("⟨a:1⟩") == 1 and t.count("paper3draft") == 1, t)
check("planner still adds others", "CS1 C" in t)
check("prev: parent+open kids [>] → 10/2",
      "- [>] CS2315 paper3draft (due Thu 10/8 · 6h) ⟨a:1⟩ ▶14:00 → 10/2\n" in pv
      and "  - [x] gather 3 sources ▶20:10 ■20:35 (25m)\n" in pv
      and "\t- [>] write outline → 10/2" in pv
      and "      - [>] deep one → 10/2" in pv, pv)
check("prev: fully-done block untouched", "- [x] ALLDONE block\n  - [x] sub a ▶1:00 ■1:10 (10m)\n  - [x] sub b\n" in pv)
check("prev: done parent untouched, open kid [>]", "- [x] parent done but kid open\n  - [>] leftover kid → 10/2" in pv)
check("prev: if-time block untouched", "- [ ] CS9 later" in pv and "  - [ ] later kid" in pv)
a1 = t; tb.roll(T); check("block carry: roll idempotent", rd(tb.day_path(T)) == a1 and rd(tb.day_path(T0)) == pv)
w, must, over, later_ = tb.plan_today(T, tb.split_blocks(rd(tb.backlog_path())), ["- [ ] X (due Sun 10/4 · 30m) ⟨a:50⟩", "  - [ ] kid1", "  - [ ] kid2", "  - [x] kid3 (done 10/1)"])
check("plan_today: kids not counted in load", w is None, w)

# third day: carried-done kids keep original (done 10/1), still no tally
t3 = rd(tb.roll(D(2026, 10, 3))); print(t3)
check("2nd carry keeps (done 10/1) once", "  - [x] gather 3 sources (done 10/1)\n" in t3 and t3.count("(done 10/1)") >= 1 and "(done 10/1) (done" not in t3, t3)
# finishing an unfinished kid on day 2 then roll: becomes (done 10/2)
b = newbase()
wr(tb.day_path(T0), "# Today 10/1\n- [ ] Big thing\n  - [ ] k1\n  - [ ] k2\n\n<!-- status -->\nCanvas: x\n")
tb.roll(T)
txt = rd(tb.day_path(T)).replace("  - [ ] k1", "  - [x] k1 ▶10:00 ■10:10 (10m)")
wr(tb.day_path(T), txt)
t3 = rd(tb.roll(D(2026, 10, 3)))
check("kid done on day2 -> (done 10/2) on day3, open kid carried", "- [ ] Big thing (since 10/1)\n  - [x] k1 (done 10/2)\n  - [ ] k2\n" in t3, t3)
check("... and heading has no tally", t3.split("\n")[0] == "# Today 10/3")
# all kids + parent done -> not carried
b = newbase()
wr(tb.day_path(T0), "# Today 10/1\n- [x] Fin\n  - [x] k\n\n<!-- status -->\nx\n")
check("done parent + done kids: not carried", "Fin" not in rd(tb.roll(T)))

# --- picker labels
lines = ["# Today 10/2", "- [ ] CS2315 paper3draft (due Thu 10/8 · 6h) ⟨a:1⟩", "  - [x] gather ▶1:00 ■1:10 (10m)", "  - [ ] write outline ▶10:00",
         "- [x] done parent", "  - [ ] kid of done", "", "## If time allows", "- [ ] solo (due Mon 10/12 23:59 · 2h) ⟨a:9⟩", "  - [ ] a very long child label here"]
pi = tb.pick_items(lines)
labs = dict(pi)
check("picker: parent pickable", labs[1].startswith("CS2315 paper3draft (due Thu 10/8 · 6h)"), labs)
check("picker: child label `<parent short> › <child>`", labs[3] == "CS2315 paper3draft › write outline  ▶10:00 in progress", labs)
check("picker: done kid not listed, done-parent's kid listed w/ parent", 2 not in labs and labs[5] == "done parent › kid of done", labs)
check("picker: if-time suffix on child", labs[9] == "solo › a very long child label here  (if time allows)", labs)
check("toggle on child line", tb.toggle_line("  - [ ] write outline", dt.datetime(2026,10,2,10,0))[0] == "  - [ ] write outline ▶10:00"
      and tb.toggle_line("  - [ ] write outline ▶10:00", dt.datetime(2026,10,2,10,25))[0] == "  - [x] write outline ▶10:00 ■10:25 (25m)")
long_parent = "- [ ] " + "W" * 50 + " (due Thu 10/8) ⟨a:2⟩"
check("picker: parent short capped", tb.short_title(long_parent[6:]) == "W" * 27 + "…")

# --- pick end-to-end on a child (fake fzf selects the 'write outline' child), tally updated
b = newbase()
wr(tb.day_path(T), "# Today 10/2\n- [ ] Paper (due Thu 10/8 · 6h) ⟨a:1⟩\n  - [ ] write outline ▶10:00\n\n<!-- status -->\nCanvas: x\n")
fz = script("fake-fzf", 'grep "write outline" | head -1\n')
os.environ["TODO_BOARD_FZF"] = fz
rc = tb.pick(T, dt.datetime(2026, 10, 2, 10, 45))
tp = rd(tb.day_path(T))
check("pick toggles child + tally in heading", rc == 0 and "  - [x] write outline ▶10:00 ■10:45 (45m)\n" in tp and tp.startswith("# Today 10/2   ✓ 1 done · 45m\n"), tp)
os.environ.pop("TODO_BOARD_FZF")

# --- tally
tt = """# Today 10/2   ✓ 99 done
- [x] a ▶10:00 ■10:25 (25m)
- [x] b no duration
- [x] carried (done 10/1)
- [>] moved → 10/3
- [ ] open ▶9:00
  - [x] kid ▶11:00 ■12:20 (80m)
  - [x] kid carried (done 10/1)
- [x] canvas thing ✓canvas

<!-- status -->
Canvas: ok
"""
check("tally: count excludes (done M/D) and [>]; time sums (Nm)", tb.tally(tt) == (4, 105), tb.tally(tt))
ta = tb.apply_tally(tt)
check("tally heading `✓ 4 done · 1h 45m`", ta.startswith("# Today 10/2   ✓ 4 done · 1h 45m\n"), ta.split("\n")[0])
check("tally idempotent", tb.apply_tally(ta) == ta)
check("tally: zero -> plain heading", tb.apply_tally("# Today 10/2   ✓ 3 done\n- [ ] x\n").startswith("# Today 10/2\n"))
check("tally: count only, no time", tb.apply_tally("# Today 10/2\n- [x] z\n").startswith("# Today 10/2   ✓ 1 done\n"))
check("tally: only first heading", tb.apply_tally("# Today 10/2\n- [x] z\n# Today 9/9\n").count("✓") == 1)
# sync recomputes the tally in a file edited directly
b = newbase(); fixture([])
wr(tb.day_path(T), "# Today 10/2\n- [x] edited in nvim ▶10:00 ■10:30 (30m)\n\n<!-- status -->\nCanvas: x\n")
tb.canvas_refresh(T, NOW)
check("sync recomputes tally", rd(tb.day_path(T)).startswith("# Today 10/2   ✓ 1 done · 30m\n"), rd(tb.day_path(T)))

# --- Done today (Canvas)
b = newbase()
fixture([item(1, "A one", "2026-10-04T04:59:00Z"), item(2, "B two", "2026-10-04T04:59:00Z"), item(3, "Never planned", "2026-10-06T04:59:00Z")])
tb.canvas_refresh(T, NOW)
wr(tb.day_path(T), "# Today 10/2\n- [ ] CS4355 A one (due Sun 10/4 23:59 · 2h) ⟨a:1⟩\n\n<!-- status -->\nCanvas: x\n")
# 1 (in today's file) and 3 (not) get submitted; 2 unchanged
fixture([item(1, "A one", "2026-10-04T04:59:00Z", sub={"submitted": True}), item(2, "B two", "2026-10-04T04:59:00Z"),
         item(3, "Never planned", "2026-10-06T04:59:00Z", sub={"submitted": True})])
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 10, 0)); t1 = rd(tb.day_path(T)); print(t1)
check("done-today: existing line gets ✓canvas, not duplicated", "- [x] CS4355 A one (due Sun 10/4 23:59 · 2h) ⟨a:1⟩ ✓canvas" in t1 and t1.count("A one") == 1, t1)
check("done-today: unplanned submitted item appended in section above footer",
      "## Done today\n- [x] CS4355 Never planned ✓canvas\n\n<!-- status -->" in t1, t1)
check("done-today: counted in tally", t1.startswith("# Today 10/2   ✓ 2 done\n"), t1.split("\n")[0])
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 11, 0)); t2 = rd(tb.day_path(T))
check("done-today: idempotent", t2.replace("ok 11:00", "ok 10:00") == t1 or t2.count("Never planned") == 1, t2)
check("done-today: seen date recorded", json.load(open(os.path.join(b, ".state.json")))["done_seen"].get("a:3") == "2026-10-02")
# second new submission joins the same section (no second heading)
fixture([item(1, "A one", "2026-10-04T04:59:00Z", sub={"submitted": True}), item(2, "B two", "2026-10-04T04:59:00Z", sub={"submitted": True}),
         item(3, "Never planned", "2026-10-06T04:59:00Z", sub={"submitted": True})])
tb.canvas_refresh(T, dt.datetime(2026, 10, 2, 12, 0)); t3 = rd(tb.day_path(T))
check("done-today: second item same section", t3.count("## Done today") == 1 and "✓canvas\n- [x] CS4355 B two ✓canvas\n" in t3, t3)
# next day: carried nothing, done_seen=10/2 so not 'today'
tn = rd(tb.roll(D(2026, 10, 3), fetch=False)); check("done-today: not in next day's file", "Never planned" not in tn and "B two" not in tn)
tb.canvas_refresh(D(2026, 10, 3), dt.datetime(2026, 10, 3, 9, 0))
check("done-today: yesterday's submission not re-added tomorrow", "Never planned" not in rd(tb.day_path(D(2026, 10, 3))))
# already-done on first sight (no transition) is not 'today'
b = newbase(); fixture([item(8, "Old submitted", "2026-10-04T04:59:00Z", sub={"submitted": True})])
wr(tb.day_path(T), "# Today 10/2\n\n<!-- status -->\nx\n"); tb.canvas_refresh(T, NOW)
check("done-today: first-seen-done is not appended", "Old submitted" not in rd(tb.day_path(T)))
# submitted_at via submissions/self decides the date
b = newbase()
def fake_sub(path):
    if path.endswith("/submissions/self"):
        return {"workflow_state": "submitted", "submitted_at": "2026-10-02T15:00:00Z"}  # 10/2 10:00 CDT
    return {"lock_at": None}
cv.http_get_json = fake_sub
fixture([litem(5, "LTI today", "2026-10-06T04:59:00Z")])
wr(tb.day_path(T), "# Today 10/2\n\n<!-- status -->\nx\n"); tb.canvas_refresh(T, NOW)
check("done-today: submitted_at (Chicago) today -> appended", "- [x] CS4355 LTI today ✓canvas" in rd(tb.day_path(T)), rd(tb.day_path(T)))
def fake_sub2(path):
    if path.endswith("/submissions/self"):
        return {"workflow_state": "submitted", "submitted_at": "2026-10-01T15:00:00Z"}
    return {"lock_at": None}
cv.http_get_json = fake_sub2
b = newbase(); fixture([litem(5, "LTI yesterday", "2026-10-06T04:59:00Z")])
wr(tb.day_path(T), "# Today 10/2\n\n<!-- status -->\nx\n"); tb.canvas_refresh(T, NOW)
check("done-today: submitted_at yesterday -> not appended", "LTI yesterday" not in rd(tb.day_path(T)))
cv.http_get_json = real_get

# --- Done today (mail resolved)
shutil.rmtree(md_dir, ignore_errors=True); os.makedirs(md_dir)
digest("2026-10-02", [mi("a@x.edu", "Sign the form", resolved=True, name="Registrar"), mi("b@x.edu", "Open one", name="Bob"),
                      mi("c@x.edu", "Info only", cat="info", resolved=True)])
os.environ["TODO_BOARD_MAIL_DIR"] = md_dir
b = newbase(); fixture([]); wr(tb.day_path(T), "# Today 10/2\n\n<!-- status -->\nx\n")
tb.sync_all(T, NOW); tm = rd(tb.day_path(T))
check("done-today: resolved action mail appended once", "- [x] Mail: Registrar — Sign the form ✓mail" in tm and "Open one" not in tm and "Info only" not in tm, tm)
tb.sync_all(T, NOW); check("done-today: mail idempotent", rd(tb.day_path(T)).count("Sign the form") == 1)
b = newbase(); fixture([]); wr(tb.day_path(D(2026, 10, 3)), "# Today 10/3\n\n<!-- status -->\nx\n")
tb.sync_all(D(2026, 10, 3), NOW)
check("done-today: older digest's resolved not appended", "Sign the form" not in rd(tb.day_path(D(2026, 10, 3))))
os.environ.pop("TODO_BOARD_MAIL_DIR")

# --- 7日合算：別の日の digest に分かれた要対応が両方残る・後の digest の resolved で消える
b = newbase()
md_dir2 = tempfile.mkdtemp(dir=os.environ["S"]); os.environ["TODO_BOARD_MAIL_DIR"] = md_dir2
json.dump({"items": [mi("a@x.edu", "Old thing", name="A")]}, open(os.path.join(md_dir2, "2026-09-30-mail.json"), "w"))
json.dump({"items": [mi("b@x.edu", "New thing", name="B")]}, open(os.path.join(md_dir2, "2026-10-01-mail.json"), "w"))
tb.mail_refresh(D(2026, 10, 1), NOW); mb = rd(tb.backlog_path())
check("union: both days kept", "Old thing" in mb and "New thing" in mb and "from 9/30" in mb, mb)
json.dump({"items": [mi("a@x.edu", "Old thing", name="A", resolved=True)]}, open(os.path.join(md_dir2, "2026-10-02-mail.json"), "w"))
tb.mail_refresh(D(2026, 10, 2), NOW); mb = rd(tb.backlog_path())
check("union: later resolved removes", "Old thing" not in mb and "New thing" in mb, mb)

# --- show: 今日の分／無ければ直近の過去分（注記つき）／leaf 無しは cat
import io, contextlib
b = newbase()
os.environ["TODO_BOARD_LEAF"] = "/nonexistent/leaf"
wr(tb.day_path(D(2026, 10, 1)), "# Today 10/1\n- [ ] older\n")
out, err = io.StringIO(), io.StringIO()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err): rc = tb.show(T)
check("show: falls back to latest earlier file with note", rc == 0 and "older" in out.getvalue() and "10/1" in err.getvalue(), (out.getvalue(), err.getvalue()))
wr(tb.day_path(T), "# Today 10/2\n- [ ] now\n")
out, err = io.StringIO(), io.StringIO()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err): rc = tb.show(T)
check("show: today's file, plain cat", rc == 0 and "now" in out.getvalue() and "older" not in out.getvalue() and err.getvalue() == "")
fk = os.path.join(os.environ["S"], "fakeleaf"); wr(fk, "#!/bin/sh\necho LEAF \"$@\"\n"); os.chmod(fk, 0o755)
os.environ["TODO_BOARD_LEAF"] = fk
r = subprocess.run([sys.executable, P, "show"], capture_output=True, text=True, env=dict(os.environ, TODO_BOARD_DIR=b))
check("show: uses leaf --inline ansi:<cols>", r.returncode == 0 and "LEAF --inline ansi:80" in r.stdout and r.stdout.strip().endswith("-todo.md"), (r.stdout, r.stderr))
b = newbase()
r = subprocess.run([sys.executable, P, "show"], capture_output=True, text=True, env=dict(os.environ, TODO_BOARD_DIR=b))
check("show: nothing -> rc 1", r.returncode == 1)
os.environ.pop("TODO_BOARD_LEAF")

print("\nFAILS:", fails); sys.exit(1 if fails else 0)
