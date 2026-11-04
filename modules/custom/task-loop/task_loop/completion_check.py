"""completion-check：Canvas で提出済みの課題に対応する Linear issue を閉じる（3時間ごと）。

背景：提出しても Linear は自動では変わらない（LIF-207 は Canvas で採点済みなのに Todo のままだった）。
やること（全部コードで決める。Claude は呼ばない）：
  1. Linear(LIF) の issue から、説明文の目印で Canvas の課題 ID に結びつく「親」と、
     `parent: LIF-n` 行で親に結びつく「子」を拾う
  2. Canvas の提出状態を見て分類する
       提出済み → 親と、開いている子を Done にして、親に1回コメント
       0 点     → 親と、開いている子を Canceled にして、親に1回コメント
       それ以外 → 触らない
  3. 既に Done / Canceled の issue は対象外なので、再実行しても二重コメントにならない
  4. 期限の追従（2026-11-03）。Canvas の期限 → 親、親の期限 → 子。
     自動で付けた期限だけを追う：前回自動で付けた値を due-sync.json に覚えておき、
     今の期限がその値のままなら新しい期限に書き換える。違っていたら「手で変えた」とみなして以後は触らない。

`--apply` を付けたときだけ書き込む。付けなければ計画表を出すだけ（既定が dry-run）。
"""

from __future__ import annotations

import re
import sys

from . import canvas, orca, state

JOB = "completion-check"
TEAM = "LIF"
OPEN = {"unstarted", "started", "backlog"}

# 親：`marker: a:<id>` / 生行の `⟨a:<id>⟩`（どちらも `a:<id>` を含む）、新しい形式の `Canvas assignment <id>`。
# `p:` 系（課題でない予定）の目印は拾わない。
_ASSIGN_RE = re.compile(r"(?:\ba:|Canvas assignment\s+)(\d+)")
# 子：親への参照は Linear の relation ではなく説明文の行。
_PARENT_RE = re.compile(r"^\s*parent:\s*([A-Z]+-\d+)\s*$", re.MULTILINE)


def assignment_id(description: str | None) -> str | None:
    """説明文から Canvas の課題 ID を取り出す。無ければ None。"""
    m = _ASSIGN_RE.search(description or "")
    return m.group(1) if m else None


def parent_ref(description: str | None) -> str | None:
    """子 issue の説明文から親の識別子（LIF-n）を取り出す。"""
    m = _PARENT_RE.search(description or "")
    return m.group(1) if m else None


def classify(sub: dict | None) -> str:
    """Canvas の submission を 'submitted' / 'zero' / 'none' に分類する。

    zyBook など外部ツールの課題は、別の場所で終えると submitted_at が null のまま
    graded + 点数だけが返ってくる（成績パススルー）。だから点数も提出の証拠に数える。
    """
    if not sub:
        return "none"
    ws = sub.get("workflow_state")
    score = sub.get("score")
    if sub.get("submitted_at") or ws in ("submitted", "pending_review"):
        return "submitted"
    if ws == "graded" and score is not None:
        return "submitted" if score > 0 else "zero"
    return "none"


def build_index(issues: list[dict]) -> tuple[dict[str, str], dict[str, list[dict]]]:
    """(親候補: 識別子→課題ID, 子: 親の識別子→子 issue のリスト) を作る。

    `parent:` 行を持つ issue は子として扱い、親候補にはしない（子が課題 ID も書いていても二重処理しない）。
    """
    roots: dict[str, str] = {}
    children: dict[str, list[dict]] = {}
    for iss in issues:
        desc = iss.get("description")
        p = parent_ref(desc)
        if p:
            children.setdefault(p, []).append(iss)
            continue
        aid = assignment_id(desc)
        if aid:
            roots[iss["identifier"]] = aid
    return roots, children


def canvas_local_date(due_at: str | None) -> str | None:
    """Canvas の due_at（UTC）を学校の現地日付（America/Chicago）にする。23:59 CT 締切が翌日 UTC になるため。"""
    if not due_at:
        return None
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.fromisoformat(due_at.replace("Z", "+00:00")).astimezone(ZoneInfo("America/Chicago")).date().isoformat()


def _follow(current: str | None, target: str | None, rec: str | None) -> tuple[str | None, str | None]:
    """(書き込む期限 or None, 新しい記録 or None)。

    - 期限が空 → target を書いて記録する
    - 記録なし・今の期限 = target → 記録だけ始める（基準を取る）
    - 記録あり・今の期限 = 記録 → target に追従（変わっていれば書く）
    - それ以外（手で付けた・手で変えた）→ 書かず、記録も捨てる
    """
    if not target:
        return None, rec if current == rec else None
    if current is None:
        return target, target
    if rec is None:
        return None, target if current == target else None
    if current == rec:
        return (target if target != current else None), target
    return None, None


def plan_due_sync(issues: list[dict], assignments: dict[str, dict], rec: dict) -> tuple[list[tuple[str, str]], dict]:
    """(書く (識別子, 期限) の一覧, 新しい記録 {"parent": {}, "child": {}})。純粋関数。

    親は Canvas の期限に、子は親の（書き換え後の）期限に追う。開いている issue だけ。
    """
    roots, _ = build_index(issues)
    by_id = {i["identifier"]: i for i in issues}
    new = {"parent": {}, "child": {}}
    writes: list[tuple[str, str]] = []
    after: dict[str, str | None] = {i["identifier"]: i.get("dueDate") for i in issues}
    for ident, aid in roots.items():
        iss = by_id[ident]
        if orca.state_type(iss) not in OPEN:
            continue
        target = canvas_local_date((assignments.get(aid) or {}).get("due_at"))
        w, r = _follow(iss.get("dueDate"), target, rec.get("parent", {}).get(ident))
        if w:
            writes.append((ident, w))
            after[ident] = w
        if r:
            new["parent"][ident] = r
    for iss in issues:
        p = parent_ref(iss.get("description"))
        if not p or orca.state_type(iss) not in OPEN:
            continue
        w, r = _follow(iss.get("dueDate"), after.get(p), rec.get("child", {}).get(iss["identifier"]))
        if w:
            writes.append((iss["identifier"], w))
        if r:
            new["child"][iss["identifier"]] = r
    return writes, new


def set_due_confirmed(identifier: str, due: str) -> None:
    try:
        orca.run("linear", "save-issue", identifier, "--due-date", due)
    except orca.OrcaError as e:
        if "linear_write_unconfirmed" not in str(e):
            raise
        if orca.issue(identifier).get("dueDate") != due:
            raise


def plan(issues: list[dict], assignments: dict[str, dict]) -> tuple[list[dict], list[str]]:
    """計画（実行する物）と注意書き（曖昧な物）を返す。副作用なし。"""
    roots, children = build_index(issues)
    by_id = {i["identifier"]: i for i in issues}
    items: list[dict] = []
    notes: list[str] = []

    for ident, aid in sorted(roots.items(), key=lambda kv: int(kv[0].rsplit("-", 1)[1])):
        iss = by_id[ident]
        if orca.state_type(iss) not in OPEN:
            continue
        a = assignments.get(aid)
        if a is None:
            notes.append(f"{ident}: 課題 {aid} が受講中のコースに無い（スキップ）")
            continue
        verdict = classify(a["submission"])
        if verdict == "none":
            continue
        sub = a["submission"] or {}
        kids = [k for k in children.get(ident, []) if orca.state_type(k) in OPEN]
        items.append({
            "parent": ident,
            "title": iss.get("title", ""),
            "assignment": aid,
            "verdict": verdict,
            "to": "Done" if verdict == "submitted" else "Canceled",
            "submitted_at": sub.get("submitted_at"),
            "score": sub.get("score"),
            "workflow_state": sub.get("workflow_state"),
            "children": [k["identifier"] for k in kids],
        })

    # 親が閉じている / 見つからないのに子だけ開いている物は、勝手に閉じずに報告だけする。
    for pid, kids in sorted(children.items()):
        open_kids = [k["identifier"] for k in kids if orca.state_type(k) in OPEN]
        if not open_kids:
            continue
        p = by_id.get(pid)
        if p is None:
            notes.append(f"{', '.join(open_kids)}: 親 {pid} が見つからない（子だけ開いている）")
        elif orca.state_type(p) not in OPEN:
            notes.append(f"{', '.join(open_kids)}: 親 {pid} は {orca.state_name(p)} だが子が開いている（触らない）")
    return items, notes


def comment_body(item: dict) -> str:
    kids = "、".join(item["children"])
    if item["verdict"] == "submitted":
        s = f"completion-check: Canvas で提出済みを確認（提出 {item['submitted_at'] or 'なし'}・点数 {item['score']}）。"
        return s + (f"子 {kids} も Done にした。" if kids else "")
    s = "completion-check: Canvas で 0 点（未提出のまま締切を過ぎたと判断）。Canceled にした。"
    return s + (f"子 {kids} も Canceled にした。" if kids else "")


def evidence(item: dict) -> str:
    return f"{item['workflow_state']}・提出 {item['submitted_at'] or 'なし'}・点数 {item['score']}"


def print_plan(items: list[dict], notes: list[str], tag: str) -> None:
    if not items:
        print(f"{tag}閉じる対象なし")
    for it in items:
        kids = ",".join(it["children"]) or "-"
        print(f"{tag}{it['parent']}\t{it['title'][:40]}\t{evidence(it)}\t→ {it['to']}\t子: {kids}")
    for n in notes:
        print(f"NOTE {n}")


def set_status_confirmed(identifier: str, to: str) -> None:
    """状態を変える。Orca が「反映されたか確認できない」（linear_write_unconfirmed）と返したら、
    読み直して目的の状態になっていれば成功とみなす。

    2026-11-03 の初回実行で、実際には反映されていたのに unconfirmed が返り、
    残りの子と親が手つかずのまま止まった（LIF-21・LIF-24）。
    """
    try:
        orca.set_status(identifier, to)
    except orca.OrcaError as e:
        if "linear_write_unconfirmed" not in str(e):
            raise
        if orca.state_name(orca.issue(identifier)) != to:
            raise


def main(argv: list[str]) -> int:
    apply = "--apply" in argv
    tag = "" if apply else "[dry-run] "

    try:
        issues = orca.run("linear", "list-issues", "--team", TEAM)["issues"]
        assignments = canvas.assignments_with_submission()
    except (orca.OrcaError, canvas.CanvasError, KeyError) as e:
        # 取得に失敗したまま進むと「課題が無い」と誤判定しうるので、ここで止める。
        msg = f"取得失敗: {e}"
        if apply:
            state.record_run(JOB, False, msg)
        print(f"ERROR {msg}", file=sys.stderr)
        return 1

    items, notes = plan(issues, assignments)
    print_plan(items, notes, tag)
    dues, due_rec = plan_due_sync(issues, assignments, state.load("due-sync"))
    for k, d in dues:
        print(f"{tag}期限を合わせる\t{k}\t→ {d}")
    if not apply:
        return 0

    errors: list[str] = []
    closed = 0
    for it in items:
        # 子を先に閉じる：親だけ閉じて子が残る中途半端を避ける。失敗した issue は記録して続ける。
        try:
            for k in it["children"]:
                set_status_confirmed(k, it["to"])
            set_status_confirmed(it["parent"], it["to"])
        except orca.OrcaError as e:
            errors.append(f"{it['parent']}: {e}")
            continue
        closed += 1
        try:
            orca.comment(it["parent"], comment_body(it))
        except orca.OrcaError as e:
            errors.append(f"comment {it['parent']}: {e}")
    closed_ids = {k for it in items for k in it["children"]} | {it["parent"] for it in items}
    filled = 0
    for k, d in dues:
        if k in closed_ids:
            continue
        try:
            set_due_confirmed(k, d)
            filled += 1
        except orca.OrcaError as e:
            errors.append(f"due {k}: {e}")
            due_rec["parent"].pop(k, None)
            due_rec["child"].pop(k, None)
    state.save("due-sync", due_rec)
    for e in errors:
        print(f"ERROR {e}", file=sys.stderr)
    state.record_run(JOB, not errors, f"closed {closed}・due {filled}・notes {len(notes)}・errors {len(errors)}")
    return 1 if errors else 0
