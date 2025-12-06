#!/usr/bin/env bash

set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

BROWSER_APP="${BROWSER_APP:-Comet}"
WEZTERM_APP="${WEZTERM_APP:-WezTerm}"

SHEETS_URL="https://docs.google.com/spreadsheets/d/1p4rGvtYcqk9hfsl8PSeMlsNqFu34o8DOGM78MBn7dg4/edit?gid=0#gid=0"
GEMINI_URL="https://gemini.google.com/app"
ATCODER_URL="https://atcoder.jp"

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

space_keycode() {
  case "$1" in
    1) echo 18 ;; # 1 key
    2) echo 19 ;; # 2 key
    3) echo 20 ;; # 3 key
    4) echo 21 ;; # 4 key
    5) echo 23 ;; # 5 key
    6) echo 22 ;; # 6 key
    7) echo 26 ;; # 7 key
    8) echo 28 ;; # 8 key
    9) echo 25 ;; # 9 key
    *) echo "" ;;
  esac
}

find_window() {
  local app="$1"
  local pattern="$2"
  yabai -m query --windows \
    | jq -r --arg app "$app" --arg pattern "$pattern" '
      map(select(.app == $app and (if $pattern == "" then true else (.title | test($pattern; "i")) end)))
      | sort_by(.id)
      | first
      | .id // empty
    '
}

wait_for_window() {
  local app="$1"
  local pattern="$2"
  for _ in $(seq 1 30); do
    local win_id
    win_id="$(find_window "$app" "$pattern")"
    if [ -n "$win_id" ]; then
      echo "$win_id"
      return 0
    fi
    sleep 0.2
  done
  echo ""
  return 1
}

current_space_index() {
  yabai -m query --spaces --space | jq -r '.index'
}

window_space() {
  local win_id="$1"
  [ -z "$win_id" ] && return 0
  yabai -m query --windows --window "$win_id" | jq -r '.space // empty'
}

wezterm_in_space() {
  local space="$1"
  yabai -m query --windows | jq -r --argjson space "$space" '
    map(select(.app == "WezTerm" and (.space == $space)))
    | sort_by(.id) | first | .id // empty
  '
}

visible_space_for_display() {
  local display_id="$1"
  yabai -m query --spaces --display "$display_id" \
    | jq -r 'map(select(.visible == 1)) | first | .index // empty'
}


# $1: URL, $2: ウィンドウタイトルに一致するパターン
# 指定されたブラウザウィンドウがあればIDを返し、なければ新たに起動してIDを返す
ensure_browser_window() {
  local url="$1"
  local pattern="$2"
  local win_id

  win_id="$(find_window "$BROWSER_APP" "$pattern")"

  # "-z" : 文字列の長さが0かどうかを判定する
  if [ -z "$win_id" ]; then
    log "Launching $BROWSER_APP -> $url"

    # "-na" : アプリケーションを起動し、新しいウィンドウを開く
    open -na "$BROWSER_APP" --args --new-window "$url"
    win_id="$(wait_for_window "$BROWSER_APP" "$pattern")" || true
  fi
  echo "$win_id"
}

focus_space_by_index() {
  local index="$1"
  log "Focus request for space index $index"
  if yabai -m space --focus "$index" >/dev/null 2>&1; then
    log "Focused space via yabai"
    current_space_index
  else
    local keycode
    keycode="$(space_keycode "$index")"
    if [ -n "$keycode" ] && command -v skhd >/dev/null 2>&1; then
      log "Fallback to ctrl+$index via skhd -k"
      skhd -k "ctrl - $index" >/dev/null 2>&1 || true
      sleep 0.2
    else
      log "Space $index not found; staying on current space"
    fi
    current_space_index
  fi
}

ensure_wezterm_window() {
  local target_space_id="$1"
  local win_id

  if [ -z "$target_space_id" ]; then
    target_space_id="$(current_space_index)"
  fi
  log "Looking for WezTerm in space $target_space_id"

  # 1) use existing WezTerm in target space
  win_id="$(wezterm_in_space "$target_space_id")"
  if [ -n "$win_id" ]; then
    log "Found WezTerm in target space ($win_id)"
    echo "$win_id"
    return 0
  fi

  # helper: wait for a WezTerm window in the target space only
  wait_for_wezterm_in_space() {
    local space_id="$1"
    local attempt
    for attempt in $(seq 1 20); do
      local found
      found="$(yabai -m query --windows | jq -r --argjson space "$space_id" '
        map(select(.app == "WezTerm" and (.space == $space)))
        | sort_by(.id) | first | .id // empty
      ')"
      if [ -n "$found" ]; then
        echo "$found"
        return 0
      fi
      sleep 0.15
    done
    echo ""
    return 1
  }

  # 2) spawn a new WezTerm window (assumes current space == target)
  if command -v wezterm >/dev/null 2>&1; then
    log "Spawning WezTerm via wezterm cli"
    wezterm cli spawn --new-window >/dev/null 2>&1 || true
    win_id="$(wait_for_wezterm_in_space "$target_space_id")" || true
    if [ -n "$win_id" ]; then
      log "WezTerm appeared in target space via wezterm cli ($win_id)"
      echo "$win_id"
      return 0
    fi
  fi

  log "Launching $WEZTERM_APP"
  open -na "$WEZTERM_APP" || true
  win_id="$(wait_for_wezterm_in_space "$target_space_id")" || true
  if [ -n "$win_id" ]; then
    log "WezTerm appeared in target space via open -na ($win_id)"
    echo "$win_id"
    return 0
  fi

  # 違うSpaceに出た場合は諦めてフォーカスしない
  log "Failed to place WezTerm in target space"
  echo ""
}

move_and_grid() {
  local window_id="$1"
  local display_id="$2"
  local space_id="$3"
  local grid_spec="$4"
  [ -z "$window_id" ] && return 0
  if yabai -m query --windows --window "$window_id" | jq -e '.isFloating == 0' >/dev/null 2>&1; then
    yabai -m window "$window_id" --toggle float || true
  fi
  [ -n "$space_id" ] && yabai -m window "$window_id" --space "$space_id"
  yabai -m window "$window_id" --display "$display_id"
  yabai -m window "$window_id" --grid "$grid_spec"
}

stack_windows() {
  local anchor="$1"
  local target="$2"
  [ -z "$anchor" ] && return 0
  [ -z "$target" ] && return 0
  yabai -m window "$target" --stack "$anchor" || true
}

detect_displays() {
  local json
  json="$(yabai -m query --displays)"
  local count main sub
  count="$(printf '%s' "$json" | jq 'length')"
  if [ "$count" -eq 1 ]; then
    main="$(printf '%s' "$json" | jq -r '.[0].index')"
    printf '%s\n' "$count $main "
    return 0
  fi
  main="$(printf '%s' "$json" | jq -r 'map(select(.isBuiltin == false)) | first | .index // empty')"
  sub="$(printf '%s' "$json" | jq -r 'map(select(.isBuiltin == true)) | first | .index // empty')"
  if [ -z "$main" ]; then
    main="$(printf '%s' "$json" | jq -r 'first(.[]).index')"
  fi
  if [ -z "$sub" ]; then
    sub="$(printf '%s' "$json" | jq -r 'last(.[]).index')"
  fi
  printf '%s\n' "$count $main $sub"
}

layout_single() {
  local display_id="$1"
  local space_id="$2"
  local sheet="$3"
  local gemini="$4"
  local atcoder="$5"
  local wezterm="$6"

  move_and_grid "$wezterm" "$display_id" "$space_id" "1:2:0:1:1:1"
  move_and_grid "$sheet" "$display_id" "$space_id" "2:2:0:0:1:1"
  move_and_grid "$gemini" "$display_id" "$space_id" "2:2:1:0:1:1"
  move_and_grid "$atcoder" "$display_id" "$space_id" "2:2:0:0:1:1"
  stack_windows "$sheet" "$atcoder"
  [ -n "$sheet" ] && yabai -m window --focus "$sheet"
}

layout_dual() {
  local main_display="$1"
  local main_space="$2"
  local sub_display="$3"
  local sub_space="$4"
  local sheet="$5"
  local gemini="$6"
  local atcoder="$7"
  local wezterm="$8"

  move_and_grid "$atcoder" "$main_display" "$main_space" "1:2:0:0:1:1"
  move_and_grid "$wezterm" "$main_display" "$main_space" "1:2:0:1:1:1"
  move_and_grid "$sheet" "$sub_display" "$sub_space" "1:2:0:0:1:1"
  move_and_grid "$gemini" "$sub_display" "$sub_space" "1:2:0:1:1:1"
  [ -n "$sheet" ] && yabai -m window --focus "$sheet"
}

main() {
  local sheets gemini atcoder wezterm target_space_id

  target_space_id="${TARGET_SPACE_INDEX:-5}"
  log "Target space index: $target_space_id"

  local pre_wezterm
  pre_wezterm="$(wezterm_in_space "$target_space_id")"
  [ -n "$pre_wezterm" ] && log "WezTerm already present in target space before focus ($pre_wezterm)"

  focus_space_by_index "$target_space_id"
  local current_idx
  current_idx="$(current_space_index)"
  log "Current space index after focus attempt: $current_idx"

  wezterm="$(ensure_wezterm_window "$target_space_id")"
  [ -n "$wezterm" ] && yabai -m window --focus "$wezterm" || true

  # 最初のマイルストーン: ワークスペース切り替えと WezTerm 起動のみ。
  if [ "${ATCODER_OPEN_BROWSER:-0}" != "1" ]; then
    return 0
  fi

  sheets="$(ensure_browser_window "$SHEETS_URL" "Sheets|Google Sheets")"
  gemini="$(ensure_browser_window "$GEMINI_URL" "Gemini")"
  atcoder="$(ensure_browser_window "$ATCODER_URL" "AtCoder")"

  local info count main sub
  info="$(detect_displays)"
  count="$(printf '%s' "$info" | awk '{print $1}')"
  main="$(printf '%s' "$info" | awk '{print $2}')"
  sub="$(printf '%s' "$info" | awk '{print $3}')"

  if [ "$count" -le 1 ] || [ -z "$sub" ]; then
    log "Applying single-display layout (display=$main)"
    local main_space
    main_space="$(visible_space_for_display "$main")"
    layout_single "$main" "$main_space" "$sheets" "$gemini" "$atcoder" "$wezterm"
  else
    log "Applying dual-display layout (main=$main, sub=$sub)"
    local main_space sub_space
    main_space="$(visible_space_for_display "$main")"
    sub_space="$(visible_space_for_display "$sub")"
    layout_dual "$main" "$main_space" "$sub" "$sub_space" "$sheets" "$gemini" "$atcoder" "$wezterm"
  fi
}

main "$@"
