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
import glob
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from datetime import date, datetime, timedelta
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
CANDIDATE_DAYS = 14   # これだけ連続で不調なら「消す候補」に載せる
RECOVERED_SHOW_DAYS = 7

# 「そのジョブが実際に更新する物」。ログは何も出力しないジョブがあるので、健全性はこちらで見る。
# 2026-11-03：cp-dashboard 系はログに何も書かない（正常でもログが古い）のに不調と誤報していた。
# (ラベルの部分一致キー → (パス（glob 可）, 許す古さ（秒）))。長いキー優先。
ARTIFACTS = {
    "cp-dashboard-stopwatch": ("~/.cache/cp-dashboard/poller.lock", 30 * 60),
    "cp-dashboard": ("~/cp-dashboard/out/update.log", 2 * 3600),
    "record-blocks": ("~/Library/RecordBlocks/*.json", 2 * DAY),
    "mail-check": ("~/.local/state/mail-check/last-ok-date", 3 * DAY),
}


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


def parse_launchctl_print(text: str) -> dict:
    """`launchctl print <domain>/<label>` の出力から判定に要る所だけ抜く。

    state / last_exit（'(never exited)' など数字でなければ None）/ spawn_failure。
    起動失敗の型：'penalty box' が出る、または 'spawn scheduled' が出ていて終了コードが 0 以外。
    """
    m = re.search(r"^\s*state = (.+?)\s*$", text, re.MULTILINE)
    state_ = m.group(1) if m else None
    m = re.search(r"last exit code = (-?\d+)", text)
    last_exit = int(m.group(1)) if m else None
    spawn = "penalty box" in text or ("spawn scheduled" in text and last_exit not in (None, 0))
    m = re.search(r"^\s*runs = (\d+)\s*$", text, re.MULTILINE)
    runs = int(m.group(1)) if m else None
    return {"state": state_, "last_exit": last_exit, "spawn_failure": spawn, "runs": runs}


def boot_time() -> int | None:
    try:
        out = subprocess.run(["sysctl", "-n", "kern.boottime"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r"sec = (\d+)", out)
    return int(m.group(1)) if m else None


def too_few_runs(plist: dict, lc: dict, now: int) -> str | None:
    """StartInterval のジョブが、読み込まれてからの予定回数に比べて極端に少ししか起動していない。

    2026-10-29〜11-03 の youtube-gate-enforce：10分ごとのはずが5日で runs = 1、終了コードは 0、
    penalty box の表示も消えていた＝他の印では見えなかった。runs は再読み込みで 0 に戻るので、
    起点は「起動時刻と plist の更新時刻（switch で書き換わる。symlink は追わない）の遅い方」。
    スリープ中は StartInterval が発火しない・ユーザーの agent はログイン時に読まれる、ので予定回数は
    多めに出る。誤検知を避けるため「予定 50 回以上で、実績がその 1/10 未満」のときだけ不調にする（検証 H4）。
    """
    interval = plist.get("StartInterval")
    runs, loaded = lc.get("runs"), lc.get("loaded_at")
    if not interval or plist.get("KeepAlive") or runs is None or loaded is None:
        return None
    expected = (now - loaded) // int(interval)
    if expected >= 50 and runs * 10 < expected:
        return f"起動回数が予定よりずっと少ない（{runs} 回／予定 {expected} 回）"
    return None


def launchctl_print(domain_label: str) -> dict | None:
    """読めなければ None（その場合は判定材料に使わない）。"""
    try:
        p = subprocess.run(["launchctl", "print", domain_label], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0 or not p.stdout:
        return None
    return parse_launchctl_print(p.stdout)


def artifact_spec(label: str) -> dict | None:
    for key in sorted(ARTIFACTS, key=len, reverse=True):
        if key in label:
            path, max_age = ARTIFACTS[key]
            return {"path": path, "max_age": max_age, "name": Path(path).name}
    return None


def artifact_mtime(spec: dict) -> int | None:
    """glob に当たったファイルのうち最も新しい更新時刻。無ければ None。"""
    best = None
    for f in glob.glob(os.path.expanduser(spec["path"])):
        try:
            m = int(os.stat(f).st_mtime)
        except OSError:
            continue
        best = m if best is None else max(best, m)
    return best


def classify_launchd(row: dict, plist: dict, last: int | None, now: int,
                     lc: dict | None = None, art: dict | None = None) -> tuple[str, list[str]]:
    """('ok' | 'bad' | 'unknown', 理由) を返す。

    順序：①launchctl print（終了コード・状態・起動失敗）②ジョブの成果物の古さ ③ログの古さ（最後の手段）。
    不調と決めるのは「積極的な証拠」があるときだけ：
      終了ステータスが 0 以外 / 起動失敗 / 成果物が古い / 常駐なのに動いていない。
    ログが古いだけでは不調にしない（何も出力しない正常なジョブがある）→ 不明。
    art = {"name", "max_age", "mtime"}。last = ログの最終更新（無ければ None）。
    """
    _, limit, keep = summarize_schedule(plist)
    reasons: list[str] = []
    lc = lc or {}
    running = row["pid"] is not None or lc.get("state") == "running"
    exit_code = lc["last_exit"] if lc.get("last_exit") is not None else row["status"]
    if keep:
        if not running:
            reasons.append("常駐のはずが動いていない")
    elif exit_code not in (None, 0) and not running:
        reasons.append(f"前回の終了ステータスが {exit_code}")
    if lc.get("spawn_failure"):
        reasons.append("起動に失敗し続けている（launchd が再試行待ちになっている）")
    few = too_few_runs(plist, lc, now)
    if few:
        reasons.append(few)
    art_fresh = False
    if art and art.get("mtime") is not None:
        age = now - art["mtime"]
        if age > art["max_age"]:
            reasons.append(f"{art['name']} が更新されていない（{fmt_age(age)}前）")
        else:
            art_fresh = True
    if reasons:
        return "bad", reasons
    if art_fresh or limit is None:
        return "ok", []
    if last is not None and now - last <= limit:
        return "ok", []
    if last is None:
        return "unknown", ["動いた形跡を確かめる物が無い（ログも成果物も無い）"]
    return "unknown", [f"ログが{fmt_age(now - last)}前から更新されていない（ログを出さないジョブなら正常。不調とは決められない）"]


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
    uid = os.getuid()
    boot = boot_time()
    sources = [
        (["launchctl", "list"], False, HOME / "Library/LaunchAgents", "launchd（ユーザー）", f"gui/{uid}"),
        (["launchctl", "print", "system"], True, Path("/Library/LaunchDaemons"), "root（system）", "system"),
    ]
    for cmd, system, plist_dir, kind, domain in sources:
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired) as e:
            errors.append(f"{' '.join(cmd)}: {e}")
            continue
        for row in parse_launchctl_rows(out, system=system):
            plist = load_plist(plist_dir / f"{row['label']}.plist")
            sched, limit, _ = summarize_schedule(plist)
            last = newest_log_mtime(plist)
            lc = launchctl_print(f"{domain}/{row['label']}")
            if lc is not None:
                try:
                    pm = int(os.lstat(plist_dir / f"{row['label']}.plist").st_mtime)
                except OSError:
                    pm = None
                starts = [t for t in (boot, pm) if t]
                lc["loaded_at"] = max(starts) if starts else None
            art = None
            spec = artifact_spec(row["label"])
            if spec:
                art = {**spec, "mtime": artifact_mtime(spec)}
            tl = task_loop_job(row["label"])
            note = ""
            st_ok_since = None
            if tl:
                # task-loop のジョブは自前の実行記録が正。失敗は終了ステータスでは見えない（0 で終わる）ので別に見る。
                st = _load_status(tl)
                if st.get("last_run") and limit is not None:
                    art = {"name": f"実行記録（status/{tl}.json）", "max_age": limit, "mtime": int(st["last_run"])}
                if st.get("last_run") and st.get("ok") is False:
                    note = f"最後の実行が失敗: {st.get('summary', '')}"
                    st_ok_since = st.get("last_ok")
            health, reasons = classify_launchd(row, plist, last, now, lc, art)
            if note:
                health, reasons = "bad", reasons + [note]
            # 失敗がいつ始まったかの目安（証拠があるときだけ）：成果物が最後に更新された時刻 / 最後に成功した時刻。
            since = None
            if health == "bad":
                if art and art.get("mtime") is not None and now - art["mtime"] > art["max_age"]:
                    since = art["mtime"]
                elif st_ok_since:
                    since = int(st_ok_since)
            shown_last = max([t for t in (last, art["mtime"] if art else None) if t] or [0]) or None
            entries.append({
                "key": row["label"], "name": describe(row["label"]), "label": row["label"], "kind": kind,
                "schedule": sched, "last": shown_last, "health": health, "reasons": reasons, "since": since,
            })
    return entries, errors


def _load_status(job: str) -> dict:
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
            "key": "orca:" + str(a.get("id") or a.get("name", "")), "since": None,
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


def render(now: int, entries: list[dict], planned: list[dict], errors: list[str],
           links: dict | None = None, candidates: list[dict] | None = None,
           recovered: list[dict] | None = None) -> tuple[str, int]:
    """説明文の Markdown と不調件数を返す。純粋関数。

    links：key → 調査 issue の表示（'LIF-212' や '（作成予定）'）。candidates：消す候補。recovered：最近直った物。
    """
    links = links or {}
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
            link = f"　→ 調査: {links[e['key']]}" if e.get("key") in links else ""
            L.append(f"- **{e['name']}**（{e['kind']}）: {'、'.join(e['reasons'])}{link}")
        for m in errors:
            L.append(f"- 取得失敗: {m}")
        L.append("")

    if recovered:
        L.append("## 最近直った物")
        for r in recovered:
            link = f"（調査 issue {r['issue']} は閉じてよければ閉じて）" if r.get("issue") else ""
            L.append(f"- {r['name']}: {r['on']} に正常に戻った{link}")
        L.append("")

    if candidates:
        L += ["## 消す候補（2週間止まっていて困っていない）", ""]
        for c in candidates:
            L.append(f"- **{c['name']}**（{c['kind']}）: {c['days']}日間ずっと不調（{c['first']} から）")
        L += ["", "止まっていても困らなかったなら要らない。残すなら理由を、消すならそう返事して。", ""]

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
        "不調の物には「仕組みの不調を調べる：…」という調査 issue を1件ずつ自動で作る（Agent ラベル。直るまで同じ物を使い回す）。",
        "ログが古いだけでは不調にしない（何も出力しない正常なジョブがあるため）。確かな証拠が無いときは「不明」と書く。",
        "何も自動では消さない。消すのは自分で決める。",
        "",
    ]
    return "\n".join(L), len(bad)


# --- 履歴（不調の継続日数）と調査 issue -----------------------------------


def update_history(jobs: dict, entries: list[dict], today: date) -> tuple[dict, list[dict], list[dict]]:
    """ジョブごとの履歴を更新して (新しい jobs, 消す候補, 最近直った物) を返す。純粋関数。

    first_unhealthy：不調が続いている最初の日。直ったら消す。証拠から始まりが分かるなら（成果物の
    最終更新など）は表示に使うだけで、起点は検知した日。不明（unknown）は不調でも正常でもないので何も変えない。
    """
    jobs = {k: dict(v) for k, v in jobs.items()}
    candidates: list[dict] = []
    recovered: list[dict] = []
    for e in entries:
        j = jobs.get(e["key"], {})
        if e["health"] == "bad":
            # 成果物の日付で遡らない：もともと更新しない成果物だと、検知初日に消す候補へ飛ぶため（検証 M1）。
            first = j.get("first_unhealthy") or today.isoformat()
            j["first_unhealthy"] = first
            j.pop("recovered_on", None)
            days = (today - date.fromisoformat(first)).days
            if days >= CANDIDATE_DAYS:
                candidates.append({**e, "days": days, "first": first})
        elif e["health"] == "ok" and j.pop("first_unhealthy", None):
            j["recovered_on"] = today.isoformat()
        if e["health"] == "ok" and j.get("recovered_on"):
            on = date.fromisoformat(j["recovered_on"])
            if (today - on).days <= RECOVERED_SHOW_DAYS:
                recovered.append({"name": e["name"], "on": j["recovered_on"], "issue": j.get("investigation")})
            else:
                j.pop("recovered_on")
        if j:
            jobs[e["key"]] = j
    return jobs, candidates, recovered


def issue_is_open(ident: str) -> bool:
    """調査 issue がまだ開いているか。読めないときは開いている扱い（二重に作らないため）。
    ただし issue が存在しないと分かるときだけ閉じた扱い。"""
    try:
        return orca.state_type(orca.issue(ident)) not in ("completed", "canceled")
    except orca.OrcaError as e:
        return "not found" not in str(e).lower()


def open_titles(parent: str | None) -> dict | None:
    """親の子のうち開いている issue の {タイトル: 識別子}。読めなければ None（＝今回は作らない）。"""
    if not parent:
        return {}
    try:
        r = orca.run("linear", "list-issues", "--team", TEAM, "--parent-id", parent)
        return {i["title"]: i["identifier"] for i in (r.get("issues") or [])
                if i.get("title") and orca.state_type(i) not in ("completed", "canceled")}
    except Exception:
        return None


def plan_investigations(entries: list[dict], jobs: dict, is_open=issue_is_open,
                        existing: dict | None = None) -> list[dict]:
    """不調で、開いている調査 issue がまだ無い物（＝新しく作る物）を返す。
    以前の issue が閉じていて再び不調になった物は、新しく作る側に入る。
    existing＝親の子の開いている issue のタイトル表。同じタイトルがあれば作らず、その ID を jobs に戻す
    （作成後に ID を保存しそこねても、翌朝タイトルで拾うので二重にならない。検証 H1・H2）。"""
    existing = existing or {}
    todo = []
    for e in entries:
        if e["health"] != "bad":
            continue
        hit = existing.get(investigation_title(e))
        if hit:
            jobs.setdefault(e["key"], {})["investigation"] = hit
            continue
        ident = jobs.get(e["key"], {}).get("investigation")
        if ident and is_open(ident):
            continue
        todo.append(e)
    return todo


def investigation_title(e: dict) -> str:
    return f"仕組みの不調を調べる：{e['name']}"


def investigation_body(e: dict, today: date) -> str:
    ev = "\n".join(f"- {r}" for r in e["reasons"]) or "- （理由なし）"
    return "\n".join([
        f"自動化の棚卸し（{INVENTORY_PARENT_HINT}）が見つけた不調を、原因まで調べてほしい。",
        "",
        "## 対象",
        f"- 名前: {e['name']}",
        f"- ジョブ: `{e['label']}`（{e['kind']}）",
        f"- 周期: {e['schedule']}",
        f"- 検知した日: {today.isoformat()}",
        "",
        "## 見つかった証拠",
        ev,
        "",
        "## 調べる人（エージェント）へ",
        "1. 読み取りだけで診断する。plist・ログ・nix のモジュール（~/nix-darwin-conf）・`launchctl print` を読む。",
        "2. 根本原因を見つける（なぜ止まったか、いつからか）。",
        "3. 直し方を提案として書く。コミットできる差分の説明でもよい。",
        "4. 最後に、本人がやる手番を1つだけ書く。例：`sudo darwin-rebuild switch`／「消す／残すを選ぶ」。",
        "",
        "やってはいけないこと：sudo の実行、`launchctl bootout`・`kickstart` などの書き込み系、ファイルや設定の削除、",
        "darwin-rebuild の実行。診断と提案だけをする。",
        "",
        "この issue が閉じるまで、同じジョブの調査 issue は増えない。直ったら閉じてよい。",
    ])


INVENTORY_PARENT_HINT = "LIF-211"


def create_investigation(e: dict, parent: str, today: date) -> str:
    """調査 issue を作って識別子を返す。作成後に確認できない（unconfirmed）ときは親の子を探して確かめる。"""
    title = investigation_title(e)
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(investigation_body(e, today))
        path = f.name
    try:
        args = ["linear", "create", "--team", TEAM, "--title", title, "--label", "Agent",
                "--priority", "medium", "--parent", parent, "--body-file", path]
        err = None
        try:
            ident = _find_identifier(orca.run(*args))
        except Exception as x:  # 書けたのに失敗に見えることがある（unconfirmed・タイムアウト）
            ident, err = None, x
        if not ident:
            ident = (open_titles(parent) or {}).get(title)
        if not ident:
            raise orca.OrcaError(f"作成を確認できない（翌朝タイトルで照合する）: {err}")
    finally:
        os.unlink(path)
    return ident


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


def _find_by_title(title: str) -> str | None:
    try:
        r = orca.run("linear", "list-issues", "--team", TEAM)
    except Exception:
        return None
    for i in r.get("issues") or []:
        if i.get("title") == title and orca.state_type(i) not in ("completed", "canceled"):
            return i["identifier"]
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
    ident = _find_by_title(TITLE)
    if not ident:
        try:
            ident = _find_identifier(orca.run("linear", "create", "--team", TEAM, "--title", TITLE,
                                              "--label", "Human", "--body-file", body_file))
        except Exception:
            ident = None
        ident = ident or _find_by_title(TITLE)
    if not ident:
        raise orca.OrcaError("棚卸し issue を作れたか確認できない（翌朝タイトルで照合する）")
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
    today = datetime.fromtimestamp(now).date()

    errors: list[str] = []
    entries, e1 = collect_launchd(now)
    orca_entries, e2 = collect_orca()
    planned, e3 = collect_planned()
    errors += e1 + e2 + e3
    entries = entries + orca_entries

    saved = state.load(JOB)
    jobs, candidates, recovered = update_history(saved.get("jobs", {}), entries, today)
    parent = saved.get("issue")
    existing = open_titles(parent)
    if existing is None:
        errors.append("調査 issue の一覧を読めなかったので、今回は新しく作らない（二重作成を避けるため）")
        todo = []
    else:
        todo = plan_investigations(entries, jobs, existing=existing)
    links = {k: v["investigation"] for k, v in jobs.items() if v.get("investigation")}
    bad_keys = {e["key"] for e in entries if e["health"] == "bad"}
    links = {k: v for k, v in links.items() if k in bad_keys}
    for e in todo:
        links[e["key"]] = "（作成予定）"

    if not apply:
        body, _ = render(now, entries, planned, errors, links, candidates, recovered)
        print(body)
        print("\n[dry-run] 作る調査 issue：" + ("なし" if not todo else ""))
        for e in todo:
            print(f"  - {investigation_title(e)}（Agent・medium・親 {INVENTORY_PARENT_HINT}）")
        return 0

    try:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
            f.write("(作成中)")
            first_path = f.name
        try:
            ident = ensure_issue(first_path)
        finally:
            os.unlink(first_path)
        for e in todo:
            try:
                new = create_investigation(e, ident, today)
            except orca.OrcaError as err:
                errors.append(f"調査 issue の作成に失敗（{e['name']}）: {err}")
                links.pop(e["key"], None)
                continue
            jobs.setdefault(e["key"], {})["investigation"] = new
            links[e["key"]] = new
            state.save(JOB, {**state.load(JOB), "jobs": jobs})
        state.save(JOB, {**state.load(JOB), "jobs": jobs})
        body, n_bad = render(now, entries, planned, errors, links, candidates, recovered)
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
            f.write(body)
            path = f.name
        try:
            write_issue(ident, path, n_bad)
        finally:
            os.unlink(path)
    except Exception as e:  # 想定外の例外でも、ここまでに作った issue の ID は保存済み
        state.save(JOB, {**state.load(JOB), "jobs": jobs})
        state.record_run(JOB, False, f"書き込み失敗: {e}")
        print(f"ERROR {e}", file=sys.stderr)
        return 1
    state.record_run(JOB, True, f"{ident}・不調 {n_bad}・調査 issue 新規 {len(todo)}・取得失敗 {len(errors)}")
    return 0
