#!/usr/bin/env bash
# update.sh — fetch → render → 壁紙差し替えの1サイクル（launchd エントリポイント）
# fetch の失敗は許容してキャッシュで描画する（set -e にしない）。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$ROOT/upstream"
OUT="$ROOT/out"
LOG="$OUT/update.log"
CACHE="$HOME/.cache/cp-dashboard"
NOVI_COOKIE="$HOME/tmp/cp-navisteps/auth_session"

mkdir -p "$OUT" "$CACHE"

# ログは 500 行で切り詰め
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 500 ]; then
    tail -n 250 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

USER_MAIN="$(python3 -c "import json;print(json.load(open('$ROOT/watchlist.json'))[0])")"

log "cycle start (user=$USER_MAIN)"

if python3 "$UP/fetch_stats.py" --user "$USER_MAIN" \
        --output "$CACHE/stats_$USER_MAIN.json" >> "$LOG" 2>&1; then
    log "fetch_stats ok"
else
    log "fetch_stats FAILED — rendering from cache"
fi

if [ -s "$NOVI_COOKIE" ]; then
    if python3 "$UP/fetch_novisteps.py" --one >> "$LOG" 2>&1; then
        log "fetch_novisteps ok"
    else
        log "fetch_novisteps FAILED — rendering from cache"
    fi
else
    log "novisteps cookie missing ($NOVI_COOKIE) — skip"
fi

# draft-v1 盤面のデータ生成（キャッシュから直接計算・fetch 失敗時は stale で描く）
if python3 "$ROOT/web/gen-draft-data.py" >> "$LOG" 2>&1; then
    log "gen-draft-data ok"
else
    log "gen-draft-data FAILED — rendering stale draft-data"
fi

if "$ROOT/bin/render-wallpaper.sh" >> "$LOG" 2>&1; then
    log "render ok"
else
    log "render FAILED"
    exit 1
fi

# スクリーンセーバー用: 主画面の PNG を saver の sandbox コンテナへコピー
# (legacyScreenSaver は HOME がコンテナに remap されるため直接 ~/cp-dashboard を読めない)
latest="$OUT/wall-main.png"
if [ -s "$latest" ]; then
    for c in com.apple.ScreenSaver.Engine.legacyScreenSaver com.apple.wallpaper.extension.legacy; do
        cdir="$HOME/Library/Containers/$c/Data/cp-dash"
        mkdir -p "$cdir" 2>/dev/null && cp "$latest" "$cdir/wall.png" 2>/dev/null \
            || log "saver copy FAILED for $c"
    done
    log "saver png updated"
fi

log "cycle done"
