#!/bin/sh
# statusline の中継：Claude Code が statusline に渡す JSON から rate_limits を保存し、
# そのまま Orca の statusline hook に渡す。
#
# 目的：無人の Orca automation の precheck が「枠が余っているか」を読むため
# （vault の task-execution-redesign-linear-orca §2026-10-31）。
# Claude Code には残り枠を返すコマンドが無く、statusline の入力にだけ rate_limits が載る。
# Orca は受け取っても保存しない（~/Library/Application Support/orca を確認済み）。
#
# 保存先：~/.cache/claude-ratelimits/latest.json（payload 全体ではなく受信時刻と rate_limits だけ）。
# 更新されるのは Claude のセッションが動いている間だけ。読む側は resets_at を過ぎていたら
# 使用率0とみなす。
payload=$(cat)

case "$payload" in
  *'"rate_limits"'*)
    dir="$HOME/.cache/claude-ratelimits"
    mkdir -p "$dir"
    tmp="$dir/.latest.$$"
    if printf '%s' "$payload" | /usr/bin/python3 -I -c '
import json, sys, time
d = json.load(sys.stdin)
rl = d.get("rate_limits")
if rl is None:
    sys.exit(1)
json.dump({"received_at": int(time.time()), "rate_limits": rl}, sys.stdout)
' >"$tmp" 2>/dev/null; then
      mv "$tmp" "$dir/latest.json"
    else
      rm -f "$tmp"
    fi
    ;;
esac

# Orca の statusline hook へ（元の settings.json の非 Windows 分岐と同じ呼び方）。
orca_hook="$HOME/.orca/agent-hooks/claude-statusline.sh"
if [ -f "$orca_hook" ] && [ -r "$orca_hook" ] && [ -x "$orca_hook" ]; then
  printf '%s' "$payload" | /bin/sh "$orca_hook"
fi
