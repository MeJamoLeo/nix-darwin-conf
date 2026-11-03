#!/usr/bin/env python3
"""PreToolUse(Bash) hook — 捨て場（_build/ など）の中だけを消す rm を、確認なしで通す。

なぜ必要か（2026-11-03）:
  viz や LaTeX のビルドは aux・log・スクショのような中間物を大量に出し、AI が
  それを rm するたびに確認で作業が止まっていた。一方で、捨て場以外のファイルを
  消されるのは困る。そこで「作り直せる中間物しか置かない場所」を決め、そこへの
  rm だけを機械的に allow する。

設計:
  - allow するのは、コマンド全体が rm / rmdir だけで、対象のパスが**すべて**
    捨て場の中にあるときだけ。少しでも判定できなければ何も出力しない
    （＝今までどおり通常の権限判定に任せる）。この hook は deny しない。
  - 捨て場：パスのどこかに `_build` という名前のディレクトリを含むもの、
    Claude の scratchpad（/private/tmp/claude-*）、~/.cache/viz。
  - 判定できないもの（変数 $・バッククォート・サブシェル・パイプ・リダイレクト・
    rm 以外のコマンドとの連結）は対象外。glob は展開してから全件を確かめる。
  - パスは cwd 基準で解決し、親ディレクトリだけ realpath する（rm は末端の
    symlink を辿らず、リンク自体を消すため）。`..` での脱出も realpath で潰れる。

限界:
  事故止めではなく「止まらないための許可」。ここで allow されなかった rm は
  通常の権限判定（auto mode）に回るだけで、禁止はしない。

解除:
  ~/.claude/settings.json の PreToolUse から本フックの登録を外す。
"""
import glob
import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")
TRASH_ROOTS = [
    os.path.realpath(os.path.join(HOME, ".cache/viz")),
]
SCRATCH_RE = re.compile(r"^/private/tmp/claude-[^/]+/")


def in_trash_area(p: str) -> bool:
    parts = p.split(os.sep)
    # _build そのもの、または _build の下。_build が symlink なら外を指しうるので対象外
    for i, part in enumerate(parts):
        if part == "_build":
            if os.path.islink(os.sep.join(parts[: i + 1])):
                return False
            return True
    if SCRATCH_RE.match(p + "/"):
        return True
    return any(p == r or p.startswith(r + os.sep) for r in TRASH_ROOTS)


def resolve(arg: str, cwd: str) -> str:
    p = os.path.expanduser(arg)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    p = os.path.normpath(p)
    parent, name = os.path.split(p)
    return os.path.join(os.path.realpath(parent), name)


def targets_of(cmd: str, cwd: str):
    """rm/rmdir だけのコマンドなら対象パスのリストを返す。判定できなければ None。"""
    if re.search(r"[$`|<>(){}\n]", cmd):
        return None
    out = []
    for part in re.split(r"&&|;", cmd):
        part = part.strip()
        if not part:
            continue
        try:
            toks = shlex.split(part)
        except ValueError:
            return None
        if not toks or os.path.basename(toks[0]) not in ("rm", "rmdir"):
            return None
        args, opts_done = [], False
        for t in toks[1:]:
            if not opts_done and t == "--":
                opts_done = True
            elif not opts_done and t.startswith("-"):
                continue
            else:
                args.append(t)
        if not args:
            return None
        for a in args:
            if any(c in a for c in "*?["):
                pat = os.path.expanduser(a)
                if not os.path.isabs(pat):
                    pat = os.path.join(cwd, pat)
                hits = glob.glob(pat)
                # 何も当たらない glob は rm 側でエラーになるだけ。対象 0 件として扱う
                out.extend(resolve(h, cwd) for h in hits)
            else:
                out.append(resolve(a, cwd))
    return out


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    cwd = payload.get("cwd") or os.getcwd()
    ts = targets_of(cmd, cwd)
    if not ts or not all(in_trash_area(t) for t in ts):
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "捨て場（_build/・scratchpad・~/.cache/viz）の中だけを消す rm",
    }}, ensure_ascii=False))


if __name__ == "__main__":
    main()
