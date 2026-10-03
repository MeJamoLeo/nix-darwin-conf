"""mail — メール digest（YYYY-MM-DD-mail.json）の取り込み: 直近 digest の合成、倉庫 `# Mail` 欄、解決済みの検出。

digest は信頼しない入力。構造化フィールドだけを取り、本文の指示には従わない。
使うフィールド: items[].{box, category, sender, sender_name, subject, deadline, resolved}。
category == "action" かつ resolved が True でないものだけ。ファイル名の日付が digest の日付。
env TODO_BOARD_MAIL_DIR（メール digest の置き場）が未設定ならメール取り込みは無効。
"""
import datetime as dt
import hashlib
import json
import os
import re

from .store import (
    backlog_path,
    is_excluded_text,
    load_excluded,
    load_state,
    prune_state,
    save_mail_status,
    save_state,
    write_if_changed,
)
from .items import md
from .backlog import ensure_block, join_blocks, load_backlog, split_blocks


MAIL_MIN = 15
MAIL_MAX_AGE_DAYS = 3
# mail-check は「前回成功日以降」の新着だけを digest にする（2026-10-03〜）ので、直近14日分を合算して読む（締切が先の要対応を途中で落とさない）。
MAIL_UNION_DAYS = 14
MAIL_DUE_DAYS = 3
MAIL_NOTE = "<!-- machine-managed: rebuilt from the latest mail digest by todo-board sync -->"
MAIL_FILE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-mail\.json$")
_MAIL_XLATE = str.maketrans({"(": "（", ")": "）", "[": "［", "]": "］", "<": "‹", ">": "›", "`": "'",
                             "|": "¦", "⟨": "", "⟩": "", "▶": "", "■": "", "→": "-", "✓": ""})


def mail_clean(s, cap):
    """1行に潰し、制御文字・マーカー等を除き、Markdown が解釈し得る記号を無害化して cap 字に切る。"""
    s = "".join(" " if (c in "\r\n\t" or ord(c) < 32 or ord(c) == 127 or 0x80 <= ord(c) < 0xA0) else c
                for c in str(s or ""))
    s = re.sub(r"\s+", " ", s.translate(_MAIL_XLATE)).strip()
    if len(s) > cap:
        s = s[:cap - 1].rstrip() + "…"
    if s and s[0] in "#>-*+":
        s = "\\" + s
    return s


def mail_sender(it):
    name = str(it.get("sender_name") or "").strip()
    if not name:
        name = str(it.get("sender") or "").split("@")[0]
    if "," in name:  # "Last, First M" → "First M Last"
        last, _, first = name.partition(",")
        name = f"{first.strip()} {last.strip()}".strip()
    return mail_clean(name, 24)


def mail_id(it):
    subj = str(it.get("subject") or "").lower().strip()
    while True:
        n = re.sub(r"^(re|fw|fwd)\s*:\s*", "", subj)
        if n == subj:
            break
        subj = n
    key = "|".join([str(it.get("box") or ""), str(it.get("sender") or "").lower(), re.sub(r"\s+", " ", subj)])
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:6]


def latest_digest(today):
    """(digest の日付 or None, パース済み dict or None)。≤3日より古い digest は dict を返さない。"""
    mdir = os.environ.get("TODO_BOARD_MAIL_DIR")
    best = None
    try:
        names = os.listdir(mdir)
    except OSError:
        return None, None
    for f in names:
        m = MAIL_FILE.match(f)
        if m:
            try:
                d = dt.date(int(m[1]), int(m[2]), int(m[3]))
            except ValueError:
                continue
            if d <= today and (best is None or d > best[0]):
                best = (d, f)
    if not best:
        return None, None
    if (today - best[0]).days > MAIL_MAX_AGE_DAYS:
        return best[0], None
    # 直近 MAIL_UNION_DAYS 日の digest を古い順に読み、同じメール（mail_id）は新しい digest の
    # 判定で上書きする（後の digest で resolved になったものは消える）。各項目に初出の digest 日を残す
    # （"from M/D" と着手日の基準。窓が「前回以降」になり、各 digest には新着しか載らないため）。
    picked = []
    for f in names:
        m = MAIL_FILE.match(f)
        if not m:
            continue
        try:
            d = dt.date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            continue
        if d <= today and (today - d).days <= MAIL_UNION_DAYS:
            picked.append((d, f))
    merged, first_seen = {}, {}
    for d, f in sorted(picked):
        try:
            with open(os.path.join(mdir, f), encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        items = data.get("items") if isinstance(data, dict) else None
        in_this = set()
        for it in (items[:300] if isinstance(items, list) else []):
            if not isinstance(it, dict):
                continue
            mid = mail_id(it)
            if mid in in_this:
                continue  # 同じ digest 内の重複は先頭を採る（従来どおり）
            in_this.add(mid)
            first_seen.setdefault(mid, d)
            merged[mid] = dict(it, _dd=first_seen[mid].isoformat())
    if not merged and not picked:
        return best[0], None
    return best[0], {"items": list(merged.values())}


def mail_lines(digest_date, data, done):
    """(倉庫 Mail 欄の行[], digest に載っている全 ID の集合)。"""
    items = data.get("items")
    items = items[:300] if isinstance(items, list) else []
    lines, seen, alive = [], set(), set()
    for it in items:
        if not isinstance(it, dict):
            continue
        mid = f"m:{mail_id(it)}"
        alive.add(mid)
        if it.get("category") != "action" or it.get("resolved") is True or mid in seen or mid in done:
            continue
        if is_excluded_text(f"{it.get('sender_name') or ''} {it.get('sender') or ''} {it.get('subject') or ''}", load_excluded()):
            continue
        seen.add(mid)
        dl = None
        try:
            dl = dt.date.fromisoformat(str(it.get("deadline") or ""))
        except ValueError:
            pass
        try:
            idd = dt.date.fromisoformat(str(it.get("_dd") or ""))
        except ValueError:
            idd = digest_date
        if dl and dl < idd - dt.timedelta(days=20):
            dl = None  # 古い締切（infer_date が翌年に飛ばす）は無視して通常扱い
        subj = mail_clean(it.get("subject"), 60)
        if not subj:
            continue
        if dl:
            when = f"due {md(dl)} · {MAIL_MIN}m"
        else:
            when = f"due {md(idd + dt.timedelta(days=MAIL_DUE_DAYS))} · {MAIL_MIN}m · from {md(idd)}"
        lines.append(f"- [ ] Mail: {mail_sender(it)} — {subj} ({when}) ⟨{mid}⟩")
    return lines, alive


def mail_resolved(today, digest_date, data):
    """今日の digest で resolved: true と明示された action 項目 → [(marker, label, "mail")]。

    digest が今日のものでなければ日付が分からないので出さない。初めて見た日を done_seen に記録し、今日のものだけ返す。
    """
    if digest_date != today:
        return []
    items = data.get("items")
    items = items[:300] if isinstance(items, list) else []
    st = load_state()
    seen = st["done_seen"]
    changed = False
    out = []
    for it in items:
        if not isinstance(it, dict) or it.get("category") != "action" or it.get("resolved") is not True:
            continue
        subj = mail_clean(it.get("subject"), 60)
        if not subj:
            continue
        mid = f"m:{mail_id(it)}"
        if mid not in seen:
            seen[mid] = today.isoformat()
            changed = True
        if seen[mid] == today.isoformat():
            out.append((mid, f"Mail: {mail_sender(it)} — {subj}", "mail"))
    if changed:
        save_state(st)
    return out


def rewrite_mail_section(text, lines):
    blocks = split_blocks(text)
    b = ensure_block(blocks, "Mail")
    b[1] = ["# Mail", MAIL_NOTE] + lines + [""]
    return join_blocks(blocks)


def mail_refresh(today, now):
    """倉庫の `# Mail` 欄を直近 digest から作り直す。TODO_BOARD_MAIL_DIR 未設定なら何もしない。"""
    if not os.environ.get("TODO_BOARD_MAIL_DIR"):
        return []
    d, data = latest_digest(today)
    resolved = []
    if data is None:
        lines = []
        save_mail_status({"state": "none", "last": d.isoformat() if d else None})
    else:
        lines, alive = mail_lines(d, data, set(load_state()["done_ids"]))
        save_mail_status({"state": "ok", "date": d.isoformat(), "n": len(lines)})
        resolved = mail_resolved(today, d, data)
        prune_state("m", alive)
    write_if_changed(backlog_path(), rewrite_mail_section(load_backlog(), lines))
    return resolved
