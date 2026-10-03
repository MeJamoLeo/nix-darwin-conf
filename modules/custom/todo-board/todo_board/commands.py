"""commands — サブコマンドの本体: roll（06:00 の確定）／sync（Canvas＋メール）／pick／add／edit／show。

★ 時刻刻みをエディタから切り離した理由: nvim を開く→行へ移動→キー、は1タスクごとの操作として重い
  （ユーザーの指摘 2026-10-02）。pick は fzf で選ぶだけ。どの端末でも、`ssh -t ogasawara todo` でも動く。
  fzf は env TODO_BOARD_FZF（home.nix が store パスを渡す）、無ければ PATH の fzf。

★ Today 行の繰り越しは「移動ではなくコピー」（前日側に `[>] → M/D` を残す）。
"""
import datetime as dt
import os
import re
import shutil
import subprocess
import sys

from .store import (
    atomic_write,
    backlog_path,
    day_path,
    find_prev,
    latest_day_file,
    load_state,
    read_raw,
    write_if_changed,
)
from .items import (
    DONE_MARK,
    infer_date,
    last_paren,
    MARKER,
    md,
    ORIGIN,
    parse_md_time,
    parse_size,
    STAMP,
    STARTED,
    TASK_ANY,
    TASK_OPEN,
)
from .backlog import add_someday, append_line, expire_someday, join_blocks, load_backlog, split_blocks
from .daily import (
    apply_tally,
    carry_children,
    child_map,
    DONE_TODAY,
    footer_line,
    harvest,
    harvest_file,
    migrate_inbox_in_place,
    refresh_today,
    section_of,
    STATUS_MARK,
    sync_done,
)
from .planner import candidates, IF_TIME, OVERDUE, plan_today
from .canvas import canvas_refresh
from .mail import mail_refresh


def sync_all(today, now):
    """毎時の同期＝Canvas ＋ メール。(Canvas の ok, 提出済み ID 集合) を返す。"""
    harvest_file(day_path(today), now)
    ok, done = canvas_refresh(today, now)
    mail_done = mail_refresh(today, now)
    refresh_today(today, None, now, mail_done)  # フッタ（メール状態）と解決済みメールを反映
    return ok, done


def roll(d, fetch=False, now=None):
    now = now or dt.datetime.now()
    path = day_path(d)
    blocks = split_blocks(load_backlog())
    bl_before = join_blocks(blocks)
    if os.path.exists(path):
        harvest_file(path, now)
        # 冪等。ただし移行と完了の同期だけは毎回やる（Inbox を戻し込まれても拾う）
        res = migrate_inbox_in_place(path, d, blocks)
        sync_done(read_raw(path), blocks)
        out = join_blocks(blocks)
        if out != bl_before:
            write_if_changed(backlog_path(), out)
        if res:
            atomic_write(path, apply_tally(res))
        return path
    done_ids = set()
    if fetch:
        pv = find_prev(d)
        if pv:
            harvest_file(day_path(pv), now)  # 前日に手で閉じた行を、メール欄の再構築より先に記憶する
        _, done_ids = sync_all(d, now)
        blocks = split_blocks(load_backlog())
        bl_before = join_blocks(blocks)
    prev = find_prev(d)
    carried = []
    new_prev_text = None
    if prev:
        ptext = read_raw(day_path(prev))
        harvest(ptext, now)
        sync_done(ptext, blocks)
        st = load_state()
        remembered = set(st["done_ids"]) | set(st["checked_ids"])
        overdue_markers = {c["marker"] for c in candidates(blocks, d) if c["overdue"]}
        plines = ptext.split("\n")
        parent_of = child_map(plines)
        kids = {}
        for c, par in parent_of.items():
            kids.setdefault(par, []).append(c)
        cur = "Today"
        out = list(plines)
        for i, ln in enumerate(plines):
            cur = section_of(ln, cur)
            if i in parent_of:
                continue  # 子は親の処理で一括（親だけが繰り越しを決める）
            m = TASK_ANY.match(ln)
            if not m:
                continue
            ind, stt, body = m[1], m[2], m[3]
            ch = kids.get(i, [])
            todo_kids = [c for c in ch if TASK_ANY.match(plines[c])[2] == " "]
            skip_sec = cur in (IF_TIME, OVERDUE, DONE_TODAY)
            if stt == " ":
                mm = MARKER.search(body)
                if cur == "Inbox":
                    add_someday(blocks, body, prev)
                    out[i] = f"{ind}- [>] {body} → backlog"
                elif skip_sec:
                    pass  # 翌朝に再導出するので繰り越さない
                elif mm and mm[1] in "aqd" and f"{mm[1]}:{mm[2]}" in done_ids and "Plan prep:" not in body:
                    out[i] = f"{ind}- [x] {body} ✓canvas"  # 取得で提出済みと分かった行は繰り越さない
                elif mm and f"{mm[1]}:{mm[2]}" in remembered:
                    pass  # 手で [x]／確認済みと記憶している項目は繰り越さない
                elif mm and f"{mm[1]}:{mm[2]}" in overdue_markers:
                    out[i] = f"{ind}- [>] {body} → {md(d)}"  # 締切超過は Today ではなく Overdue 欄で出し直す
                else:
                    pbody = STAMP.sub("", body).rstrip()
                    if not mm and not ORIGIN.search(pbody):
                        pbody += f" (since {md(prev)})"  # 起票印は初回だけ（マーカー付きは倉庫が出所）
                    carried.append(f"{ind}- [ ] {pbody}")
                    out[i] = f"{ind}- [>] {body} → {md(d)}"
                    carry_children(plines, ch, carried, out, prev, d)
            elif stt == "x" and todo_kids and not skip_sec and cur != "Inbox" and "✓canvas" not in body:
                # 親は終わっているが子が未完＝ブロックは未完。親は完了のまま（done 印付き）で子と一緒に持ち越す
                pbody = STAMP.sub("", body).rstrip()
                if not DONE_MARK.search(pbody):
                    pbody += f" (done {md(prev)})"
                carried.append(f"{ind}- [x] {pbody}")
                carry_children(plines, ch, carried, out, prev, d)
        new_prev_text = "\n".join(out)
    expire_someday(blocks, d)
    warn, must, over, later = plan_today(d, blocks, carried)
    text = f"# Today {md(d)}\n"
    if warn:
        text += warn + "\n"
    text += "".join(l + "\n" for l in carried + must)
    text += "\n"
    if over:
        text += f"## {OVERDUE}\n" + "".join(l + "\n" for l in over) + "\n"
    if later:
        text += f"## {IF_TIME}\n" + "".join(l + "\n" for l in later) + "\n"
    text += f"{STATUS_MARK}\n{footer_line(d)}\n"
    text = apply_tally(text)
    # 書く順: 倉庫（移行は重複許容）→ 新ファイル → 前日。途中で落ちても欠落しない
    bl_after = join_blocks(blocks)
    if bl_after != bl_before or not os.path.exists(backlog_path()):
        write_if_changed(backlog_path(), bl_after)
    atomic_write(path, text)
    if new_prev_text is not None and new_prev_text != ptext:
        atomic_write(day_path(prev), new_prev_text)
    return path


def label_of(body):
    started = "▶" in body
    done = "■" in body
    clean = MARKER.sub("", ORIGIN.sub("", STAMP.sub("", body))).strip()
    m = STARTED.search(body)
    if done:
        hint = "■ done"
    elif started and m:
        hint = f"▶{int(m[1]):02d}:{int(m[2]):02d} in progress"
    else:
        hint = ""
    return f"{clean}  {hint}".rstrip(), clean


def short_title(body, cap=28):
    """親の見出し用の短い名前（括弧以降・印を落として cap 字）。"""
    t = label_of(body)[1]
    pm = last_paren(t)
    if pm and t[:pm.start()].strip():
        t = t[:pm.start()].strip()
    return t if len(t) <= cap else t[:cap - 1].rstrip() + "…"


def pick_items(lines):
    """fzf に出す [(行 index, ラベル)]。子は `<親の短い名前> › <子>`、親も選べる。"""
    parent_of = child_map(lines)
    items = []
    cur = "Today"
    for i, ln in enumerate(lines):
        cur = section_of(ln, cur)
        m = TASK_OPEN.match(ln)
        if not m:
            continue
        lab = label_of(m[2])[0]
        if i in parent_of:
            pm = TASK_ANY.match(lines[parent_of[i]])
            lab = f"{short_title(pm[3])} › {lab}"
        if cur == IF_TIME:
            lab += "  (if time allows)"
        items.append((i, lab))
    return items


def toggle_line(line, now):
    """nvim の todo_toggle と同じ規則。(新しい行, メッセージ) を返す。変更なしは (None, msg)。"""
    if line.endswith("\r"):  # CRLF 行でも末尾の \r を保つ
        new, msg = toggle_line(line[:-1], now)
        return (new + "\r" if new else None), msg
    hm = f"{now.hour:02d}:{now.minute:02d}"
    if "■" in line:
        return None, "already finished (■)"
    m = STARTED.search(line)
    m_ = TASK_OPEN.match(line)
    clean = label_of(m_[2])[1] if m_ else line
    if "▶" not in line:
        return f"{line} ▶{hm}", f"▶ {hm} {clean}"
    if not m:
        return None, "cannot parse the ▶ time"
    mins = (now.hour * 60 + now.minute) - (int(m[1]) * 60 + int(m[2]))
    if mins < 0:
        mins += 24 * 60
    new = f"{line} ■{hm} ({mins}m)"
    new = re.sub(r"^(\s*- )\[ \]", r"\1[x]", new, count=1)
    return new, f"■ {hm} ({mins}m) {clean}"


def pick(d, now=None):
    now = now or dt.datetime.now()
    path = roll(d)
    text = read_raw(path)
    lines = text.split("\n")
    items = pick_items(lines)
    if not items:
        print("All done for today.")
        return 0
    fzf = os.environ.get("TODO_BOARD_FZF") or "fzf"
    inp = "".join(f"{i}\t{lab}\n" for i, lab in items)
    try:
        r = subprocess.run(
            [fzf, "--delimiter=\t", "--with-nth=2..", "--prompt=todo> ", "--height=40%", "--reverse"],
            input=inp, stdout=subprocess.PIPE, text=True,
        )
    except FileNotFoundError:
        print(f"fzf not found: {fzf}", file=sys.stderr)
        return 1
    sel = r.stdout.strip("\n")
    if r.returncode != 0 or not sel:
        return 0
    try:
        idx = int(sel.split("\t", 1)[0])
    except ValueError:
        print("could not parse the selection", file=sys.stderr)
        return 1
    # 書く直前に再読込して、キャプチャ時と同じ行か検証する
    fresh = read_raw(path).split("\n")
    if idx >= len(fresh) or fresh[idx] != lines[idx]:
        print("file changed meanwhile; aborted (run todo again)", file=sys.stderr)
        return 1
    new, msg = toggle_line(fresh[idx], now)
    if new is None:
        print(msg)
        return 0
    fresh[idx] = new
    atomic_write(path, apply_tally("\n".join(fresh)))
    print(msg)
    return 0


def add(d, words, due=None, on=None, size=None):
    text_in = " ".join(words).strip()
    if not text_in:
        print("todo add <text...> [--due M/D[ HH:MM]] [--on M/D] [--size 30m|2h]", file=sys.stderr)
        return 1
    if due and on:
        print("use either --due or --on", file=sys.stderr)
        return 1
    if size and parse_size(size) is None:
        print(f"bad --size '{size}' (e.g. 30m, 2h, 1h30m)", file=sys.stderr)
        return 1
    if size and not (due or on):
        print("--size needs --due or --on", file=sys.stderr)
        return 1
    try:
        spec = parse_md_time(due or on) if (due or on) else None
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 1
    blocks = split_blocks(load_backlog())
    if spec:
        mo, da, t = spec
        if infer_date(mo, da, d) is None:
            print(f"bad date {mo}/{da}", file=sys.stderr)
            return 1
        if on and t:
            print("--on takes M/D only", file=sys.stderr)
            return 1
        inner = f"{'due' if due else 'on'} {mo}/{da}" + (f" {t[0]:02d}:{t[1]:02d}" if t else "")
        if size:
            inner += f" · {size.strip()}"
        line = f"- [ ] {text_in} ({inner}) (since {md(d)})"
        append_line(blocks, "Dated", line)
    else:
        line = f"- [ ] {text_in} (since {md(d)})"
        append_line(blocks, "Someday", line)
    atomic_write(backlog_path(), join_blocks(blocks))
    print(f"+ {text_in}" + (" [dated]" if spec else " [someday]"))
    return 0


def show(today):
    """今日の日次ファイルを表示するだけ（roll しない＝副作用なし）。
    leaf（env TODO_BOARD_LEAF、既定 ~/.local/bin/leaf）があれば --inline ansi:<端末幅> で描画、無ければ素の cat。
    今日の分が無ければ直近の過去分を注記つきで出す。"""
    p = day_path(today)
    if not os.path.isfile(p):
        best = latest_day_file(today)
        if not best:
            print("todo: no daily file yet", file=sys.stderr)
            return 1
        p = best[1]
        print(f"(no file for {today:%-m/%-d} yet; showing {best[0]:%-m/%-d})", file=sys.stderr)
    leaf = os.environ.get("TODO_BOARD_LEAF") or os.path.expanduser("~/.local/bin/leaf")
    if os.path.isfile(leaf) and os.access(leaf, os.X_OK):
        cols = shutil.get_terminal_size((80, 24)).columns
        sys.stdout.flush()
        r = subprocess.run([leaf, "--inline", f"ansi:{cols}", p])
        if r.returncode == 0:
            return 0
    with open(p, encoding="utf-8") as f:
        sys.stdout.write(f.read())
    return 0


def edit(d):
    """今日のファイルを確定（roll）してから $EDITOR で開く（`todo edit`／旧名 `open`）。"""
    p = roll(d)
    ed = os.environ.get("EDITOR") or "nvim"
    os.execvp(ed, [ed, p])
