#!/usr/bin/env bash
# render-wallpaper.sh — CP dashboard 壁紙v0 パイプライン (macOS)
# 盤面は 16:9 の基準解像度で「一度だけ」描く。比率の違う画面へは、その 16:9 PNG を
# 縦横比保持で fit＋背景色レターボックスして native 解像度の PNG を作り、画面ごとに貼る。
# → 16:9 前提でチューニングした盤面が、どの比率の画面でも崩れず正しく出る。
# macOS が同一パスの再設定を無視することがあるため A/B 2ファイルを交互に使う。
# 注: launchd の bash は 3.2 なので mapfile / declare -A は使わない。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
STATE="$OUT/.wall-state"
SETWALL="$ROOT/bin/set-wallpaper"
BG="000000"                       # 盤面背景色（OLED 純黒）でレターボックス

# 基準解像度 = 一番大きい 16:9（環境変数で上書き可）
REF_W="${CP_DASH_WIDTH:-2560}"
REF_H="${CP_DASH_HEIGHT:-1440}"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || CHROME="/Applications/Chromium.app/Contents/MacOS/Chromium"
[ -x "$CHROME" ] || { echo "error: no Chrome/Chromium found" >&2; exit 1; }

mkdir -p "$OUT"

# A/B 交互
last="$(cat "$STATE" 2>/dev/null || echo b)"
next=a; [ "$last" = "a" ] && next=b
CANON="$OUT/wall-$next.png"

# 16:9 基準を一度だけ描く
python3 "$ROOT/bin/gen-inject.py" --width "$REF_W" --height "$REF_H" >/dev/null
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --window-size="${REF_W},${REF_H}" --screenshot="$CANON" \
  "file://$ROOT/web/draft-v1.html" 2>/dev/null
[ -s "$CANON" ] || { echo "error: screenshot failed" >&2; exit 1; }

# 各画面の native 解像度（取得失敗時は基準単画面フォールバック）
DISPLAYS="$("$SETWALL" --list 2>/dev/null || true)"
[ -n "$DISPLAYS" ] || DISPLAYS="$REF_W $REF_H"

# 画面ごとに fit 済み PNG を用意（同一解像度は基準をそのまま流用）
TARGETS=()
i=0
while read -r w h; do
  [ -n "$w" ] || continue
  if [ "$w" = "$REF_W" ] && [ "$h" = "$REF_H" ]; then
    TARGETS+=("$CANON")
  else
    out="$OUT/wall-fit-${w}x${h}-${next}.png"
    # 縦横比保持で (w,h) に収まる寸法を計算 → resize → 背景色でパッド
    read -r fw fh <<EOF
$(python3 -c "sw,sh,W,H=$REF_W,$REF_H,$w,$h; s=min(W/sw,H/sh); print(round(sw*s), round(sh*s))")
EOF
    sips -z "$fh" "$fw" "$CANON" -o "$out" >/dev/null 2>&1
    sips --padToHeightWidth "$h" "$w" --padColor "$BG" "$out" -o "$out" >/dev/null 2>&1
    TARGETS+=("$out")
  fi
  i=$((i+1))
done <<EOF
$DISPLAYS
EOF

# 2026-07-30: macOS 壁紙の差替は disable（透過ダッシュボード運用に移行のため）。
# 従来は "$SETWALL" "${TARGETS[@]}" で全画面に配布していたが、cp-dash-live を透過
# rgba(2,4,4,0.85) で表示する現行の運用と両立不能（下敷きが同じ盤面 PNG だと透過が
# 見えない）。壁紙は user が System Settings → Wallpaper で手動指定する前提。
# TARGETS の fit-per-display PNG は生成しても未使用だが、CPDashSaver 側から
# 参照される可能性を残して生成自体は温存する（有害でない）。
# 再有効化する場合は次行の comment を外すだけ:
# "$SETWALL" "${TARGETS[@]}"

# スクリーンセーバー / ライブ層は 16:9 基準をそのまま使う（saver は自前 aspect-fit）
cp "$CANON" "$OUT/wall-main.png"

echo "$next" > "$STATE"
echo "[render-wallpaper] 16:9 base ${REF_W}x${REF_H} → fit per display: [$(echo "$DISPLAYS" | tr '\n' ';' | sed 's/;$//')] (slot $next)"
