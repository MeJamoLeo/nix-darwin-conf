#!/usr/bin/env bash
# update.sh — fetch → render → 壁紙差し替えの1サイクル（launchd エントリポイント）
# fetch の失敗は許容してキャッシュで描画する（set -e にしない）。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$ROOT/upstream"
OUT="$ROOT/out"
LOG="$OUT/update.log"
CACHE="$HOME/.cache/cp-dashboard"
NOVI_KEYCHAIN_SERVICE="novisteps-auth-session"

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

if /usr/bin/security find-generic-password -s "$NOVI_KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
    if python3 "$UP/fetch_novisteps.py" --one >> "$LOG" 2>&1; then
        log "fetch_novisteps ok"
    else
        log "fetch_novisteps FAILED — rendering from cache"
    fi
else
    log "novisteps cookie missing (Keychain service=$NOVI_KEYCHAIN_SERVICE) — skip"
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

# スクリーンセーバー用: saver は HOME remap されたコンテナ内 cp-dash/wall.png を読む。
# コンテナへの毎サイクル cp は saver 選択後 TCC で拒否される（2026-07-20）ため、
# 実体 wall-main.png への symlink を一度だけ張る方式。既存 symlink には触らない。
latest="$OUT/wall-main.png"
if [ -s "$latest" ]; then
    for c in com.apple.ScreenSaver.Engine.legacyScreenSaver com.apple.wallpaper.extension.legacy; do
        lnk="$HOME/Library/Containers/$c/Data/cp-dash/wall.png"
        if [ ! -L "$lnk" ]; then
            mkdir -p "$(dirname "$lnk")" 2>/dev/null
            rm -f "$lnk" 2>/dev/null
            ln -s "$latest" "$lnk" 2>/dev/null \
                || log "saver symlink MISSING for $c (TCC?) — run once from terminal: ln -sf $latest $lnk"
        fi
    done
fi

log "cycle done"
