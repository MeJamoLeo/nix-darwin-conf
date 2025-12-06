#!/usr/bin/env bash

set -euo pipefail

# 使えそうなコマンド例（手で差し込む用）
# wezterm start --always-new-process
# open -na "WezTerm" --args --new-window
# skhd -k "ctrl - 5"   # Mission Control のデスクトップ5へ
# yabai -m window --space 5
# yabai -m window --toggle float

LOG_DIR="${ATCODER_LOG_DIR:-$HOME/.local/state/atcoder-mode}"
LOG_FILE="$LOG_DIR/atcoder-mode.log"
mkdir -p "$LOG_DIR"

log() {
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S')"
  printf '[atcoder-mode] %s\n' "$msg" >&2
  printf '%s %s\n' "$ts" "$msg" >>"$LOG_FILE"
}

main() {
  log "TODO: implement atcoder-mode workflow here"
}

main "$@"
