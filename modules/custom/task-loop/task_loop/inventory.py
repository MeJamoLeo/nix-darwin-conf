"""inventory：自動で動いている物の棚卸しと健全性チェックを、Linear の常設 issue に毎日書き出す（朝 7:30）。

背景（LIF-199）：自動化が増えて「何が動いていて、壊れていないか」を誰も把握できなくなった。
本人が見るのはログではなく Linear なので、常設1件の issue の説明文を毎日作り直す。
やること（全部コードで決める。Claude は呼ばない）：
  1. launchd（ユーザー / root）の常駐・定期ジョブを launchctl と plist から集める
  2. Orca の automations を `orca automations list` から集める
  3. LIF-195 の子 issue を「計画中・未作成」として集める
  4. 健全性を判定し、Markdown にして issue の説明を書き換える。
     不調があれば Todo + 期限=今日（期限ベースのビューに出す）、無ければ Backlog + 期限なし

`--apply` を付けたときだけ書き込む。付けなければ本文を出すだけ（既定が dry-run）。
"""

from __future__ import annotations

import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

from . import orca, state
from .completion_check import set_status_confirmed

JOB = "inventory"
TEAM = "LIF"
PLANNED_PARENT = "LIF-195"
TITLE = "自動化の棚卸し（毎日自動更新）"

HOME = Path.home()
USER_PREFIXES = ("org.nix-community.home.", "com.treo.", "org.nixos.")
# nix が内部で使う root ジョブ。ユーザーの自動化ではないので載せない。
SYSTEM_EXCLUDE = {"org.nixos.nix-daemon", "org.nixos.darwin-store", "org.nixos.activate-system"}

# 既知ジョブの説明（1行）。ラベルに部分一致（長い物優先）。無いラベルは生のラベルのまま載せる。
# WHY：launchd のラベルは本人が見ても何のことか分からないため、日本語の一言を手で持つ。
DESCRIPTIONS = {
    "task-loop-inventory": "この棚卸し issue を毎朝書き換える",
    "task-loop-completion-check": "提出済み課題を Done にする",
    "task-loop-workspace-cleanup": "作業場の片付け",
    "calendar-dashboard-live": "壁紙カレンダー",
    "cp-dashboard-stopwatch": "競プロのダッシュボード（ストップウォッチ）",
    "cp-dashboard-live": "競プロのダッシュボード（常駐）",
    "cp-dashboard": "競プロのダッシュボード",
    "desktop-auto": "画面ごとの壁紙切替",
    "omniwm": "ウィンドウマネージャ",
    "mail-check": "メール確認と digest",
    "record-blocks": "作業ブロック記録",
    "job-watch": "求人チェック",
    "nix-gc": "nix の掃除",
    "youtube-gate": "YouTube 制限",
    "notunes": "音楽アプリの自動起動止め",
    "claude-code-autoupdate": "Claude Code の自動更新",
}

DAY = 86400


def describe(label: str) -> str:
    # 長いキーから先に当てる（cp-dashboard-live を cp-dashboard で食わないため）。
    for key in sorted(DESCRIPTIONS, key=len, reverse=True):
        if key in label:
            return DESCRIPTIONS[key]
    return label


# --- launchd ---------------------------------------------------------------


def parse_launchctl_rows(text: str, *, system: bool) -> list[dict]:
    """`launchctl list`（ユーザー）/ `launchctl print system`（root）の行を [{label,pid,status}] にする。

    どちらも「PID  終了ステータス  ラベル」の3列。PID は '-'（ユーザー）か '0'（system）で未稼働。
    ステータスは '-' なら未確定（稼働中でまだ終わっていない等）。
    """
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) != 3:
            continue
        pid, status, label = parts
        if not label.startswith(USER_PREFIXES):
            continue
        if system and not label.startswith("org.nixos."):
            continue
        if label in SYSTEM_EXCLUDE:
            continue
        rows.append({
            "label": label,
            "pid": int(pid) if pid.isdigit() and int(pid) > 0 else None,
            "status": int(status) if re.fullmatch(r"-?\d+", status) else None,
        })
    return rows


def _entries(cal) -> list[dict]:
    if isinstance(cal, dict):
        return [cal]
    return list(cal or [])


def summarize_schedule(plist: dict) -> tuple[str, int | None, bool]:
    """plist から (人間向けの周期, 「この秒数より古ければ不調」の閾値, 常駐か) を返す。

    閾値の根拠：StartInterval は 3 周期分の余裕（Mac が寝ていても取りこぼしを1回走らせるので
    1 周期遅れは普通にある）。毎日は 2 日・毎週は 9 日・毎月は 35 日。
    閾値が None のとき（起動時だけ・周期が無い）は古さで判定しない。
    """
    keep = bool(plist.get("KeepAlive"))
    if keep:
        return "常駐", None, True
    if "StartInterval" in plist:
        sec = int(plist["StartInterval"])
        if sec % 3600 == 0:
            human = f"{sec // 3600}時間ごと"
        elif sec % 60 == 0:
            human = f"{sec // 60}分ごと"
        else:
            human = f"{sec}秒ごと"
        return human, sec * 3, False
    cals = _entries(plist.get("StartCalendarInterval"))
    if cals:
        c = cals[0]
        hm = f"{c.get('Hour', 0):02d}:{c.get('Minute', 0):02d}"
        extra = f"（他{len(cals) - 1}回）" if len(cals) > 1 else ""
        if "Weekday" in c:
            names = "日月火水木金土"
            return f"毎週{names[c['Weekday'] % 7]}曜 {hm}{extra}", 9 * DAY, False
        if "Day" in c:
            return f"毎月{c['Day']}日 {hm}{extra}", 35 * DAY, False
        return f"毎日 {hm}{extra}", 2 * DAY, False
    if plist.get("RunAtLoad"):
        return "ログイン時に1回", None, False
    return "不明", None, False


def classify_launchd(row: dict, plist: dict, last: int | None, now: int) -> tuple[str, list[str]]:
    """('ok' | 'bad' | 'unknown', 理由) を返す。

    不調：①常駐ジョブが動いていない ②非常駐で前回の終了ステータスが 0 以外
          ③周期ジョブの最終動作が閾値より古い。
    常駐ジョブの終了ステータスは見ない：再起動を繰り返す物の「前の1回」が非0でも、今動いていれば正常。
    判断材料が無いとき（ログも状態も無い）は不調にせず「不明」。
    """
    _, limit, keep = summarize_schedule(plist)
    reasons: list[str] = []
    if keep:
        if row["pid"] is None:
            reasons.append("常駐のはずが動いていない")
    elif row["status"] not in (None, 0) and row["pid"] is None:
        reasons.append(f"前回の終了ステータスが {row['status']}")
    if limit is not None and last is not None and now - last > limit:
        reasons.append(f"最終動作が古い（{fmt_age(now - last)}前）")
    if reasons:
        return "bad", reasons
    if limit is not None and last is None:
        return "unknown", ["最終動作が分からない（ログも記録も無い）"]
    return "ok", []


def newest_log_mtime(plist: dict) -> int | None:
    best = None
    for k in ("StandardOutPath", "StandardErrorPath"):
        p = plist.get(k)
        if not p:
            continue
        try:
            m = int(os.stat(p).st_mtime)
        except OSError:
            continue
        best = m if best is None else max(best, m)
    return best


def load_plist(path: Path) -> dict:
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return {}


def task_loop_job(label: str) -> str | None:
    m = re.search(r"\.task-loop-(.+)$", "." + label)
    return m.group(1) if m else None


def collect_launchd(now: int) -> tuple[list[dict], list[str]]:
    """launchd のジョブを集める。(エントリ, 取得失敗の注意書き)。"""
    entries: list[dict] = []
    errors: list[str] = []
    sources = [
        (["launchctl", "list"], False, HOME / "Library/LaunchAgents", "launchd（ユーザー）"),
        (["launchctl", "print", "system"], True, Path("/Library/LaunchDaemons"), "root（system）"),
    ]
    for cmd, system, plist_dir, kind in sources:
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired) as e:
            errors.append(f"{' '.join(cmd)}: {e}")
            continue
        for row in parse_launchctl_rows(out, system=system):
            plist = load_plist(plist_dir / f"{row['label']}.plist")
            sched, _, _ = summarize_schedule(plist)
            last = newest_log_mtime(plist)
            tl = task_loop_job(row["label"])
            note = ""
            if tl:
                # task-loop のジョブは自前の実行記録が正。失敗は終了ステータスでは見えない（0 で終わる）ので別に見る。
                st = _load_status(tl)
                if st.get("last_run"):
                    last = max(last or 0, int(st["last_run"]))
                    if st.get("ok") is False:
                        note = f"最後の実行が失敗: {st.get('summary', '')}"
            health, reasons = classify_launchd(row, plist, last, now)
            if note:
                health, reasons = "bad", reasons + [note]
            entries.append({
                "name": describe(row["label"]), "label": row["label"], "kind": kind,
                "schedule": sched, "last": last, "health": health, "reasons": reasons,
            })
    return entries, errors


def _load_status(job: str) -> dict:
    import json
    try:
        return json.loads((state.ROOT / "status" / f"{job}.json").read_text())
    except (OSError, ValueError):
        return {}


# --- Orca automations ------------------------------------------------------


def summarize_rrule(rrule: str) -> str:
    """RRULE を日本語の周期にする。読めない物は生の文字列のまま。"""
    parts = dict(p.split("=", 1) for p in (rrule or "").split(";") if "=" in p)
    freq = parts.get("FREQ")
    interval = int(parts.get("INTERVAL", "1"))
    if freq == "HOURLY":
        return ("毎時" if interval == 1 else f"{interval}時間ごと") + f" {parts.get('BYMINUTE', '0')}分"
    if freq == "DAILY" and "BYHOUR" in parts:
        return f"毎日 {int(parts['BYHOUR']):02d}:{int(parts.get('BYMINUTE', '0')):02d}"
    if freq == "WEEKLY":
        return f"毎週 {parts.get('BYDAY', '')} {parts.get('BYHOUR', '')}"
    return rrule or "不明"


def classify_orca(a: dict) -> tuple[str, list[str]]:
    # 無効化されていれば不調。有効なら正常とみなす（precheck で意図的に何もしない回があり、
    # lastRunAt の古さでは壊れているか判別できないため古さは見ない）。
    if not a.get("enabled"):
        return "bad", ["無効になっている"]
    return "ok", []


def collect_orca() -> tuple[list[dict], list[str]]:
    try:
        autos = orca.run("automations", "list")["automations"]
    except (orca.OrcaError, KeyError) as e:
        return [], [f"Orca automations の取得に失敗: {e}"]
    out = []
    for a in autos:
        health, reasons = classify_orca(a)
        last = int(a["lastRunAt"] / 1000) if a.get("lastRunAt") else None
        nxt = f"（次回 {fmt_time(int(a['nextRunAt'] / 1000))}）" if a.get("nextRunAt") and a.get("enabled") else ""
        out.append({
            "name": a.get("name", "(無名)"), "label": a.get("name", ""), "kind": "Orca",
            "schedule": summarize_rrule(a.get("rrule", "")) + nxt, "last": last,
            "health": health, "reasons": reasons,
        })
    return out, []


def collect_planned() -> tuple[list[dict], list[str]]:
    try:
        issues = orca.run("linear", "list-issues", "--team", TEAM, "--parent-id", PLANNED_PARENT)["issues"]
    except (orca.OrcaError, KeyError) as e:
        return [], [f"{PLANNED_PARENT} の子の取得に失敗: {e}"]
    return issues, []


# --- 表示 ------------------------------------------------------------------


def fmt_time(ts: int | None) -> str:
    return datetime.fromtimestamp(ts).strftime("%m/%d %H:%M") if ts else "—"


def fmt_age(sec: int) -> str:
    if sec >= DAY:
        return f"{sec // DAY}日"
    if sec >= 3600:
        return f"{sec // 3600}時間"
    return f"{max(sec // 60, 0)}分"


def _cell(s: str) -> str:
    return s.replace("|", "/").replace("\n", " ")


STATUS_MARK = {"ok": "正常", "bad": "不調", "unknown": "不明"}


def render(now: int, entries: list[dict], planned: list[dict], errors: list[str]) -> tuple[str, int]:
    """説明文の Markdown と不調件数を返す。純粋関数。"""
    bad = [e for e in entries if e["health"] == "bad"]
    unknown = [e for e in entries if e["health"] == "unknown"]
    if bad:
        verdict = f"不調 {len(bad)} 件"
    elif unknown or errors:
        verdict = f"全部正常（ただし不明 {len(unknown) + len(errors)} 件）"
    else:
        verdict = "全部正常"
    L = [f"生成日時: {datetime.fromtimestamp(now).strftime('%Y-%m-%d %H:%M')}　**{verdict}**", ""]

    if bad or errors:
        L.append("## 不調")
        for e in bad:
            L.append(f"- **{e['name']}**（{e['kind']}）: {'、'.join(e['reasons'])}")
        for m in errors:
            L.append(f"- 取得失敗: {m}")
        L.append("")

    L += ["## 動いているもの", "", "| 何をするか | いつ | 仕組み | 前回 | 状態 |", "|---|---|---|---|---|"]
    order = {"launchd（ユーザー）": 0, "root（system）": 1, "Orca": 2}
    for e in sorted(entries, key=lambda x: (order.get(x["kind"], 9), x["name"])):
        what = e["name"] if e["name"] == e["label"] else f"{e['name']}（{e['label'].rsplit('.', 1)[-1]}）"
        st = STATUS_MARK[e["health"]] + ("" if not e["reasons"] else "：" + "、".join(e["reasons"]))
        L.append(f"| {_cell(what)} | {_cell(e['schedule'])} | {e['kind']} | {fmt_time(e['last'])} | {_cell(st)} |")
    L.append("")

    L.append(f"## 計画中・未作成（{PLANNED_PARENT} の子）")
    open_planned = [i for i in planned if orca.state_type(i) not in ("completed", "canceled")]
    for i in sorted(open_planned, key=lambda i: int(i["identifier"].rsplit("-", 1)[1])):
        L.append(f"- {i['identifier']}（{orca.state_name(i)}）{i.get('title', '')}")
    if not open_planned:
        L.append("- なし")
    L.append("")

    L += [
        "## この issue について",
        "毎日 07:30 に自動で説明を書き換える（task-loop-inventory）。手で編集しても次の朝に上書きされる。",
        "不調があると Todo＋期限が今日になり、全部正常なら Backlog＋期限なしに戻る。",
        "",
    ]
    return "\n".join(L), len(bad)


# --- Linear への書き込み ---------------------------------------------------


def _find_identifier(obj) -> str | None:
    """create の結果の形に依存しないよう、入れ子の中から identifier を探す。"""
    if isinstance(obj, dict):
        if isinstance(obj.get("identifier"), str):
            return obj["identifier"]
        for v in obj.values():
            r = _find_identifier(v)
            if r:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = _find_identifier(v)
            if r:
                return r
    return None


def ensure_issue(body_file: str) -> str:
    """保存済みの ID の issue を返す。無い・消えていれば新規作成して ID を保存する。"""
    ident = state.load(JOB).get("issue")
    if ident:
        try:
            orca.issue(ident)
            return ident
        except orca.OrcaError:
            pass  # 消された・見えない → 作り直す
    r = orca.run("linear", "create", "--team", TEAM, "--title", TITLE, "--label", "Human",
                 "--body-file", body_file)
    ident = _find_identifier(r)
    if not ident:
        raise orca.OrcaError("create の結果から identifier を取れなかった")
    state.save(JOB, {**state.load(JOB), "issue": ident})
    return ident


def write_issue(ident: str, body_file: str, n_bad: int) -> None:
    due = datetime.now().strftime("%Y-%m-%d") if n_bad else "null"
    args = ["linear", "save-issue", ident, "--body-file", body_file, "--due-date", due]
    try:
        orca.run(*args)
    except orca.OrcaError as e:
        # 「書けたか確認できない」だけのことがある（completion-check と同じ）。次の行の状態確認で
        # 読み直すので、ここでは失敗扱いにしない。説明文が古いままでも翌朝また書き直される。
        if "linear_write_unconfirmed" not in str(e):
            raise
    set_status_confirmed(ident, "Todo" if n_bad else "Backlog")


def main(argv: list[str]) -> int:
    apply = "--apply" in argv
    now = int(time.time())

    errors: list[str] = []
    entries, e1 = collect_launchd(now)
    orca_entries, e2 = collect_orca()
    planned, e3 = collect_planned()
    errors += e1 + e2 + e3
    body, n_bad = render(now, entries + orca_entries, planned, errors)

    if not apply:
        print(body)
        return 0

    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(body)
        path = f.name
    try:
        ident = ensure_issue(path)
        write_issue(ident, path, n_bad)
    except orca.OrcaError as e:
        state.record_run(JOB, False, f"書き込み失敗: {e}")
        print(f"ERROR {e}", file=sys.stderr)
        return 1
    finally:
        os.unlink(path)
    state.record_run(JOB, True, f"{ident}・不調 {n_bad}・取得失敗 {len(errors)}")
    return 0
