"""report — 新着を日次 Markdown に追記し、Linear に issue を1件立てる。"""
import datetime as dt
import os
import subprocess
from . import config as C

TIER_NAME = {1: "Tier 1 オースティン周辺", 2: "Tier 2 テキサス", 3: "Tier 3 リモート（US）"}
KIND_NAME = {"newgrad": "新卒（2027 開始・OPT）", "intern": "インターン／co-op（2027・CPT）"}
CLS_ORDER = {"F1_OK": 0, "NO_H1B_ONLY": 1, "SILENT": 2, "UNKNOWN": 3}


def report_path(day):
    return os.path.join(C.BASE_DIR, day.strftime("%Y"), day.strftime("%Y%m%d") + "-jobs.md")


def line(c):
    ev = (c.get("evidence") or "-").replace("\n", " ")
    return "- [ ] %s — %s — %s — %s — %s — %s" % (c["company"], c["title"], c["location"] or "-", c["cls"], ev, c["url"])


def render(items, counts, errors, now):
    """items は EXCLUDE を除いた新着。-> 追記する Markdown 文字列。"""
    out = ["", "## %s 新着 %d 件" % (now.strftime("%H:%M"), len(items)), ""]
    for kind in ("newgrad", "intern"):
        ks = [c for c in items if c["kind"] == kind]
        if not ks:
            continue
        out += ["### " + KIND_NAME[kind], ""]
        for tier in (1, 2, 3):
            ts = sorted((c for c in ks if c["tier"] == tier), key=lambda c: (CLS_ORDER.get(c["cls"], 9), not c.get("boost"), c["company"]))
            if ts:
                out += ["#### " + TIER_NAME[tier], ""] + [line(c) for c in ts] + [""]
    if any(c["source"] == "Oracle" for c in items):
        out += ["> Oracle は自分で応募しない（紹介者に送る）", ""]
    out += ["---", "走査 %(scanned)d ／ 絞り込み後 %(filtered)d ／ 除外(EXCLUDE) %(excluded)d ／ 新着 %(new)d ／ 本文確認待ち(翌日回し) %(deferred)d" % counts]
    if errors:
        out.append("取得失敗: " + "；".join(errors))
    return "\n".join(out) + "\n"


def append(day, md):
    p = report_path(day)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    head = "" if os.path.exists(p) else "# 求人ウォッチ %s\n" % day.isoformat()
    with open(p, "a", encoding="utf-8") as f:
        f.write(head + md)
    return p


def notify_linear(n, day):
    """Linear に「見る」issue を1件（Orca CLI 経由）。Orca ランタイム不在などで失敗したら False。"""
    orca = os.environ.get("JOB_WATCH_ORCA") or C.ORCA_BIN_DEFAULT
    if not os.path.exists(orca):
        return False
    title = "求人の新着 %d 件を見る（%d/%d）" % (n, day.month, day.day)
    cmd = [orca, "linear", "create", "--team", C.LINEAR_TEAM, "--title", title, "--body", report_path(day),
           "--label", C.LINEAR_LABEL, "--priority", "high", "--due-date", day.isoformat()]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return r.returncode == 0
