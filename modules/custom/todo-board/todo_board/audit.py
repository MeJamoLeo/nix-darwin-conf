"""audit — タスクの状態を監査する。「終わっているのに閉じていない」「判断の記録が無い」「機械が壊れている」を仕分ける。

分類（2026-10-27 に本人と決めた4つ）:
  A 終わってるかも   Claude 作業時間が紐付いている（`(≈Nm)`）のに開いたまま
  B 未着手           正常。何も出さない
  C 判断の記録が無い  DEFAULT_DAYS 日以上 Today に出続けて [x] も ✗ も付いていない
  D 機械の異常       重複・ID 照合失敗・紐付かない作業時間・取得役の失敗／陳腐化

★ レポートは副産物で、本体は倉庫の書き換え（決める行＋Someday の修正タスク）。
  読ませるだけの報告には行動が付かず、黙っているのと同じになる（2026-10-06 の原則）。
★ A は提案だけで [x] は付けない（本人の指定 2026-10-27）。
  提出の証拠がある Canvas 行は既存の mark_canvas_done が閉じているので、
  ここで拾うのは「機械が完了を判定できない種類」（手書きの Dated 行・メール）だけになる。
★ 決める行は件数ぶん並べず1行にまとめる。並べると提案そのものが毎日の手番になり、
  これまで全滅した仕組み（手入力の ▶■・`todo` を叩く）と同じ形に戻る（本人の指定 2026-10-27）。
★ 決める行の同一性は内容ではなくマーカー `⟨h:audit1⟩` で持つ。本文も日付も毎日書き換わるので、
  text_hash で同一性を取ると毎日別の項目になって日次ファイルに積み上がる。
★ ネットワークを使わない。手元のファイル（日次・倉庫・.status.json）だけで判定する。
  取得役が壊れている日こそ監査が要るので、監査が取得役に依存してはいけない。
"""
import datetime as dt
import os
import re

from .store import (DAILY, backlog_path, base_dir, day_path, latest_day_file,
                    load_status, read_raw, write_if_changed)
from .items import (BLOCK_NOTE, MARKER, ORIGIN, TASK_ANY, fmt_hm, infer_past, md,
                    norm_text, parse_item, text_hash)
from .backlog import (add_someday, append_line, get_block, join_blocks,
                      load_backlog, split_blocks)
from .daily import section_of


DEFAULT_DAYS = 3  # 本人の選択（2026-10-27）。短いぶん決める行が毎日出るが、塩漬けを早く潰す
SCAN_DAYS = 120  # 初出日を遡る範囲
UNLINKED_MIN = 120  # 紐付かない Claude 作業時間がこれ以上なら異常として起票する
AUDIT_MARKER = "h:audit1"
DECIDE_BODY = ("決める：未決のまま残っているタスクを やる / ✗ で閉じる"
               "（一覧 ~/Store/30_Work/todo/audit/）")
# 繰り越し・計画の対象にならない欄（ここの行は監査でも数えない）
SKIP_SECTIONS = {"If time allows", "Done today", "Inbox"}
DROP = "✗"


def audit_dir():
    return os.path.join(base_dir(), "audit")


def audit_path(d):
    return os.path.join(audit_dir(), f"{d:%Y%m%d}-audit.md")


def line_key(body):
    mm = MARKER.search(body)
    return f"{mm[1]}:{mm[2]}" if mm else f"h:{text_hash(body)}"


def iter_daily(today, back=SCAN_DAYS):
    """(日付, 本文) を古い順に。today 以前・back 日以内の日次ファイルだけ。"""
    root = base_dir()
    out = []
    if not os.path.isdir(root):
        return out
    floor = today - dt.timedelta(days=back)
    for y in sorted(os.listdir(root)):
        yd = os.path.join(root, y)
        if not (y.isdigit() and os.path.isdir(yd)):
            continue
        for f in sorted(os.listdir(yd)):
            m = DAILY.match(f)
            if not m:
                continue
            d = dt.date(int(m[1]), int(m[2]), int(m[3]))
            if floor <= d <= today:
                out.append((d, read_raw(os.path.join(yd, f))))
    out.sort(key=lambda x: x[0])
    return out


def task_lines(text, states):
    """日次ファイルのトップレベルのタスク行 [(key, body)]。字下げした子は親に含めるので除く。

    ★ states に ">" を入れること。繰り越した行は前日のファイルでは `[>] … → M/D` に
      書き換えられるので、`[ ]` だけを数えると過去のファイルに未完が1件も見えず、
      どの項目も「初出は昨日」になる（実装中に踏んだ）。
    """
    cur = "Today"
    out = []
    for ln in text.split("\n"):
        cur = section_of(ln, cur)
        if cur in SKIP_SECTIONS or cur.startswith("Could move"):
            continue
        m = TASK_ANY.match(ln)
        if not m or m[1] or m[2] not in states:
            continue
        out.append((line_key(m[3]), m[3]))
    return out


def open_lines(text):
    """いま開いている行（`- [ ]`）だけ。"""
    return task_lines(text, " ")


def first_seen(today):
    """{key: 最初に現れた日}。`(since M/D)` の起票印があればそちらを優先（それが本人の起票日）。"""
    out = {}
    for d, text in iter_daily(today):
        for key, body in task_lines(text, " >"):
            s = ORIGIN.search(body)
            sd = infer_past(int(s[1]), int(s[2]), today) if s else None
            cand = min(sd, d) if sd else d
            if key not in out or cand < out[key]:
                out[key] = cand
    return out


def classify(today, days=DEFAULT_DAYS):
    """今いちばん新しい日次ファイルの未完行を A／C に仕分ける（B は返さない）。"""
    latest = latest_day_file(today)
    if not latest:
        return [], [], None
    d, path = latest
    text = read_raw(path)
    seen = first_seen(today)
    done_kind, undecided = [], []
    for key, body in open_lines(text):
        age = (today - seen.get(key, d)).days
        if age < days:
            continue
        # ★ 締切がまだ先のものは「未決」ではなく「進行中」。出すと、普通に回っている仕事まで
        #   毎日「決めろ」と言われることになり、決める行そのものが無視される側へ回る。
        it = parse_item(body, today)
        if it["date"] and it["date"] > today:
            continue
        rec = {"key": key, "body": body, "age": age}
        (done_kind if BLOCK_NOTE.search(body) else undecided).append(rec)
    return done_kind, undecided, d


def mail_subject(body):
    """`Mail: 送信者 — 件名` から件名だけ。送信元が Gmail／Outlook で違っても同じ件名になるように。"""
    t = norm_text(body)
    t = re.sub(r"^Mail:\s*", "", t)
    t = t.split(" — ", 1)[-1]
    t = re.sub(r"\((?:due|on|exam|was due|late OK until)[^)]*\)\s*$", "", t)
    return re.sub(r"[\s…:：]+", " ", t).strip().lower()[:40]


def machine_findings(today, blocks, days=DEFAULT_DAYS):
    """D（機械の異常）。[(安定した1行, 詳細[])]。

    起票文は毎日同じ文字列にする。件数や分数を入れると add_someday の重複判定が効かず、
    Someday に同じ修正タスクが毎日積み上がる。数字はレポート側に置く。
    """
    out = []

    # d1 同じ件名のメールが複数 ID で入っている（Gmail と Outlook の二重取り）
    #    ★ 倉庫の `# Mail` 欄だけでなく今日の欄も見る。digest から落ちた後も日次ファイルには
    #      残り続けるので、倉庫だけを見ると実例（m:504d22 / m:dcaf51）を取りこぼす。
    mail = get_block(blocks, "Mail")
    mail_bodies = []
    if mail:
        mail_bodies += [m[3] for m in (TASK_ANY.match(ln) for ln in mail[1]) if m and m[2] == " "]
    latest0 = latest_day_file(today)
    if latest0:
        mail_bodies += [b for k, b in open_lines(read_raw(latest0[1])) if k.startswith("m:")]
    if mail_bodies:
        by_subject = {}
        for body in mail_bodies:
            by_subject.setdefault(mail_subject(body), {})[line_key(body)] = norm_text(body)
        dups = [list(v.values()) for v in by_subject.values() if len(v) > 1]
        if dups:
            out.append(("todo-board 修正：同じ件名のメールが複数の ID で倉庫に入る"
                        "（Gmail と Outlook の二重取り。詳細 ~/Store/30_Work/todo/audit/）",
                        [f"{len(v)}件: {v[0]}" for v in dups]))

    # d2 今日の欄の Canvas 行が倉庫から消えている（作り直しで ID が変わった可能性）
    canvas = get_block(blocks, "Canvas")
    alive = set()
    if canvas:
        for ln in canvas[1]:
            m = TASK_ANY.match(ln)
            if m:
                alive.add(line_key(m[3]))
    latest = latest_day_file(today)
    orphans = []
    if latest and canvas:
        seen = first_seen(today)
        for key, body in open_lines(read_raw(latest[1])):
            if key[0] in "aqd" and key not in alive:
                if (today - seen.get(key, latest[0])).days >= days:
                    orphans.append(f"{key} {norm_text(body)[:60]}")
    if orphans:
        out.append(("todo-board 修正：今日の欄の Canvas 行が倉庫に無い"
                    "（ID が変わると提出しても [x] が付かない。詳細 ~/Store/30_Work/todo/audit/）",
                    orphans))

    # d3 どの行にも紐付かない Claude 作業時間
    b = load_status().get("blocks") or {}
    if b.get("unlinked_min", 0) >= UNLINKED_MIN:
        out.append(("todo-board 修正：Claude の作業時間がどの行にも紐付かない"
                    "（分類が当たっていないか、リストに無い作業。詳細 ~/Store/30_Work/todo/audit/）",
                    [f"{b.get('date')}: {fmt_hm(b['unlinked_min'])} 未紐付"]))

    # d4 取得役が失敗したまま／古い
    st = load_status()
    stale = []
    c = st.get("canvas") or {}
    if c.get("error"):
        stale.append(f"canvas: {str(c['error'])[:60]} (last ok {c.get('ok_at') or 'never'})")
    mi = st.get("mail") or {}
    ok_day = mi.get("date") or mi.get("ok_at")
    if ok_day:
        try:
            d0 = dt.date.fromisoformat(str(ok_day)[:10])
            if (today - d0).days >= 3:
                stale.append(f"mail: {(today - d0).days}日前のまま ({ok_day})")
        except ValueError:
            pass
    cal = st.get("calendar") or {}
    if cal.get("state") in ("error", "suspicious"):
        stale.append(f"calendar: {cal.get('state')}")
    if stale:
        out.append(("todo-board 修正：取得役が失敗したまま古くなっている"
                    "（黙って古い情報が出続ける。詳細 ~/Store/30_Work/todo/audit/）", stale))
    return out


def set_decide_line(blocks, today, needed):
    """倉庫の Dated にある決める行を1本に保つ。needed=False なら消す。変更があれば True。

    同一性はマーカーで持つので、本文と日付は毎回書き換えてよい。
    """
    b = get_block(blocks, "Dated")
    line = f"- [ ] {DECIDE_BODY} (on {md(today)} · 10m) ⟨{AUDIT_MARKER}⟩"
    found = False
    changed = False
    if b:
        keep = []
        for ln in b[1]:
            m = TASK_ANY.match(ln)
            if m and MARKER.search(m[3]) and line_key(m[3]) == AUDIT_MARKER:
                if not needed:
                    changed = True
                    continue  # 所見が無い日は行ごと消す（また出たら同じマーカーで戻る）
                if not found:
                    found = True
                    if ln != line:
                        changed = True
                    keep.append(line)  # [x] にされていても開き直す（翌日の所見は翌日の手番）
                else:
                    changed = True  # 2本目以降は落とす
                continue
            keep.append(ln)
        b[1] = keep
    if needed and not found:
        append_line(blocks, "Dated", line)
        changed = True
    return changed


def report(today, day, done_kind, undecided, findings, days):
    out = [f"# タスク状態の監査 {today:%Y-%m-%d}", ""]
    out.append(f"対象＝{day} の日次ファイルの未完行。{days} 日以上開いたままのものだけ出す。")
    out.append("")
    out.append(f"## 終わってるかも（作業時間が紐付いているのに未完） {len(done_kind)} 件")
    out.append("")
    for r in done_kind or []:
        out.append(f"- [{r['age']}日] {norm_text(r['body'])}")
    if not done_kind:
        out.append("- なし")
    out.append("")
    out.append(f"## 判断の記録が無い（やるとも ✗ とも決めていない） {len(undecided)} 件")
    out.append("")
    for r in undecided or []:
        out.append(f"- [{r['age']}日] {norm_text(r['body'])}")
    if not undecided:
        out.append("- なし")
    out.append("")
    out.append(f"## 機械の異常 {len(findings)} 件")
    out.append("")
    for head, detail in findings:
        out.append(f"- {head}")
        for d in detail[:10]:
            out.append(f"  - {d}")
    if not findings:
        out.append("- なし")
    out.append("")
    out.append(f"閉じ方：やるなら `[x]`、やらないと決めたら `[x] {DROP}`。"
               "どちらも付けない限り、この一覧に残り続ける。")
    return "\n".join(out) + "\n"


def run(now=None, days=DEFAULT_DAYS, dry_run=False):
    now = now or dt.datetime.now()
    today = now.date()
    done_kind, undecided, day = classify(today, days)
    if day is None:
        print("[audit] no daily file yet; nothing to audit")
        return 0
    blocks = split_blocks(load_backlog())
    before = join_blocks(blocks)
    findings = machine_findings(today, blocks, days)
    text = report(today, day, done_kind, undecided, findings, days)
    summary = (f"[audit] {today} done-kind={len(done_kind)} undecided={len(undecided)} "
               f"machine={len(findings)}")
    if dry_run:
        print(summary + " (dry-run)")
        print(text)
        return 0
    write_if_changed(audit_path(today), text)
    for head, _ in findings:
        add_someday(blocks, head, today)
    set_decide_line(blocks, today, bool(done_kind or undecided))
    after = join_blocks(blocks)
    if after != before:
        write_if_changed(backlog_path(), after)
    print(summary + f" -> {audit_path(today)}")
    return 0
