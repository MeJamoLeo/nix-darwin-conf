"""workspace-cleanup：Linear の状態に合わせて Orca のワークスペースを片付ける（1日1回）。

やること（全部コードで決める。Claude は呼ばない）：
  1. 紐づいた issue が Done / Canceled で、未コミットの変更が無い → `orca worktree rm`（--force なし）
  2. 同上で未コミットあり → 消さずに issue へコメント（同じ issue には1回だけ）
  3. 紐づいた issue が Backlog / Todo のまま → In Progress にする
     （Orca の画面から issue で始めても、状態が変わるとは限らないため）
  4. 紐づいていないワークスペース（各リポジトリの main を除く）→ 一覧を出すだけ。消さない

`--dry-run` で何も変更せずに、やる予定のことだけ表示する。
"""

from __future__ import annotations

import subprocess
import sys

from . import orca, state

JOB = "workspace-cleanup"
CLOSED = {"completed", "canceled"}
NOT_STARTED = {"backlog", "unstarted"}
IN_PROGRESS = "In Progress"


def dirty(path: str) -> bool | None:
    """未コミットの変更があるか。判定できなければ None（＝消さない側に倒す）。"""
    try:
        p = subprocess.run(
            ["git", "-C", path, "status", "--porcelain"],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    return bool(p.stdout.strip())


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    tag = "[dry-run] " if dry else ""
    mem = state.load(JOB)
    commented: set[str] = set(mem.get("commented_dirty", []))

    removed, kept, started, unlinked, errors = [], [], [], [], []

    try:
        wts = orca.worktrees()
    except orca.OrcaError as e:
        state.record_run(JOB, False, f"worktree list 失敗: {e}")
        print(f"ERROR {e}", file=sys.stderr)
        return 1

    for wt in wts:
        if wt.get("isMainWorktree") or wt.get("isArchived"):
            continue
        name = wt.get("displayName") or wt.get("path")
        ident = wt.get("linkedLinearIssue")
        if not ident:
            unlinked.append(name)
            continue
        try:
            iss = orca.issue(ident)
        except orca.OrcaError as e:
            errors.append(f"{ident}: {e}")
            continue
        st = orca.state_type(iss)

        if st in CLOSED:
            d = dirty(wt["path"])
            if d is False:
                print(f"{tag}rm {name}（{ident} は {orca.state_name(iss)}）")
                if not dry:
                    try:
                        orca.worktree_rm(wt["id"])
                    except orca.OrcaError as e:
                        errors.append(f"rm {name}: {e}")
                        continue
                removed.append(ident)
            else:
                why = "未コミットの変更あり" if d else "git の状態を確認できない"
                print(f"{tag}keep {name}（{ident} は {orca.state_name(iss)}・{why}）")
                kept.append(ident)
                if ident not in commented:
                    body = (
                        f"[workspace-cleanup] この issue は {orca.state_name(iss)} ですが、"
                        f"ワークスペース「{name}」に{why}ため消していません。"
                        f"中身を commit するか捨ててから、次の片付け（1日1回）を待つか手で消してください。\n"
                        f"`{wt['path']}`"
                    )
                    if not dry:
                        try:
                            orca.comment(ident, body)
                            commented.add(ident)
                        except orca.OrcaError as e:
                            errors.append(f"comment {ident}: {e}")
        elif st in NOT_STARTED:
            print(f"{tag}status {ident} {orca.state_name(iss)} → {IN_PROGRESS}（ワークスペース「{name}」あり）")
            if not dry:
                try:
                    orca.set_status(ident, IN_PROGRESS)
                except orca.OrcaError as e:
                    errors.append(f"status {ident}: {e}")
                    continue
            started.append(ident)

    for n in unlinked:
        print(f"{tag}unlinked {n}（issue に紐づいていない。消さない）")
    for e in errors:
        print(f"ERROR {e}", file=sys.stderr)

    if not dry:
        # 閉じた issue から消えた物は記録から外す（再び開いて閉じたら、また1回コメントする）
        mem["commented_dirty"] = sorted(commented & set(kept))
        state.save(JOB, mem)
        summary = (
            f"rm {len(removed)}・keep {len(kept)}・started {len(started)}・"
            f"unlinked {len(unlinked)}・errors {len(errors)}"
        )
        state.record_run(JOB, not errors, summary)
    return 1 if errors else 0
