#!/usr/bin/env bash

set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WEZTERM_APP="${WEZTERM_APP:-WezTerm}"

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

current_space_index() {
  yabai -m query --spaces --space | jq -r '.index'
}

wait_for_space() {
  local target="$1"
  local attempt
  for attempt in $(seq 1 20); do
    local now
    now="$(current_space_index)"
    if [ "$now" = "$target" ]; then
      log "Space focus confirmed: $now"
      echo "$now"
      return 0
    fi
    sleep 0.1
  done
  local final
  final="$(current_space_index)"
  log "Space focus not confirmed (last seen $final, target $target)"
  echo "$final"
  return 1
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

wezterm_latest_window() {
  yabai -m query --windows | jq -r '
    map(select(.app == "WezTerm")) | sort_by(.id) | last | .id // empty
  '
}

wait_for_wezterm_any() {
  local attempt
  for attempt in $(seq 1 30); do
    local found
    found="$(wezterm_latest_window)"
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
    sleep 0.2
  done
  echo ""
  return 1
}

focus_space_by_index() {
  local index="$1"
  log "Focus request for space index $index"
  if yabai -m space --focus "$index" >/dev/null 2>&1; then
    log "Focused space via yabai"
    wait_for_space "$index"
  else
    local keycode
    keycode="$(space_keycode "$index")"
    if [ -n "$keycode" ] && command -v skhd >/dev/null 2>&1; then
      log "Fallback to ctrl+$index via skhd -k"
      skhd -k "ctrl - $index" >/dev/null 2>&1 || true
      wait_for_space "$index"
    else
      log "Space $index not found; staying on current space"
      current_space_index
    fi
  fi
}

ensure_wezterm_window() {
  local target_space_id="$1"
  local win_id

  if [ -z "$target_space_id" ]; then
    target_space_id="$(current_space_index)"
  fi

  log "Ensuring WezTerm is running (target space $target_space_id)"

  # If already running, just return any window in target space (or empty).
  if pgrep -x "wezterm-gui" >/dev/null 2>&1; then
    win_id="$(wezterm_in_space "$target_space_id")"
    if [ -n "$win_id" ]; then
      log "WezTerm already running; found window in target space ($win_id)"
      echo "$win_id"
      return 0
    fi
    log "WezTerm already running; no window in target space -> spawning one"
    if command -v wezterm >/dev/null 2>&1; then
      wezterm cli spawn --new-window >/dev/null 2>&1 || true
      win_id="$(wait_for_wezterm_any)" || true
      if [ -n "$win_id" ]; then
        local win_space
        win_space="$(window_space "$win_id")"
        if [ "$win_space" != "$target_space_id" ]; then
          yabai -m window "$win_id" --space "$target_space_id" || true
          win_space="$(window_space "$win_id")"
        fi
        if [ "$win_space" = "$target_space_id" ]; then
          log "Spawned WezTerm window id $win_id"
          echo "$win_id"
          return 0
        fi
        log "Spawned WezTerm window not in target space (space=$win_space)"
      fi
      echo ""
      return 0
    else
      log "wezterm CLI not found while running; fallback open -na"
      open -na "$WEZTERM_APP" || true
      win_id="$(wait_for_wezterm_any)" || true
      if [ -n "$win_id" ]; then
        local win_space
        win_space="$(window_space "$win_id")"
        if [ "$win_space" != "$target_space_id" ]; then
          yabai -m window "$win_id" --space "$target_space_id" || true
          win_space="$(window_space "$win_id")"
        fi
        if [ "$win_space" = "$target_space_id" ]; then
          log "Spawned WezTerm via open -na id $win_id"
          echo "$win_id"
          return 0
        fi
        log "Spawned WezTerm via open -na not in target space (space=$win_space)"
      fi
      echo ""
      return 0
    fi
  fi

  # Not running: start once and return the first window we see (any space)
  if command -v wezterm >/dev/null 2>&1; then
    log "WezTerm not running; starting via wezterm start"
    wezterm start --always-new-process >/dev/null 2>&1 || true
  else
    log "wezterm CLI not found; launching via open -na"
    open -na "$WEZTERM_APP" || true
  fi

  win_id="$(wait_for_wezterm_any)" || true
  if [ -n "$win_id" ]; then
    local win_space
    win_space="$(window_space "$win_id")"
    if [ "$win_space" != "$target_space_id" ]; then
      yabai -m window "$win_id" --space "$target_space_id" || true
      win_space="$(window_space "$win_id")"
    fi
    if [ "$win_space" = "$target_space_id" ]; then
      log "WezTerm started with window id $win_id"
      echo "$win_id"
      return 0
    fi
    log "WezTerm started but not in target space (space=$win_space)"
  fi
  echo ""
}

main() {
  local wezterm target_space_id

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
}

main "$@"
