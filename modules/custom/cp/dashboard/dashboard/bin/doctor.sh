#!/usr/bin/env bash
# doctor.sh — cp-dashboard のセットアップ健診。毎 switch の activation 末尾で実行される。
# 新機体のセットアップ手順書はこれが本体：✗ の項目を、表示されたコマンドで潰して再 switch。
# 全チェック warn-only（switch は殺さない）。exit 0 固定。
set -uo pipefail

ROOT="${1:-$HOME/cp-dashboard}"
NOVI_KEYCHAIN_SERVICE="novisteps-auth-session"
WALL_STORE="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n      → %s\n' "$1" "$2"; }
meh()  { printf '  \033[33m?\033[0m %s\n' "$1"; }

echo "cp-dashboard doctor:"

# 1. swiftc (CLT) — 無いと set-wallpaper/cp-dash-live/.saver がビルドされない
if /usr/bin/xcrun -f swiftc >/dev/null 2>&1; then
    ok "swiftc (CLT)"
else
    bad "swiftc (CLT) 不在" "xcode-select --install してから再 switch（Swift 3本のビルドに必要）"
fi

# 2. Chrome/Chromium — render-wallpaper.sh の headless 描画に必要
if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] \
   || [ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]; then
    ok "Chrome (headless 描画)"
else
    bad "Chrome 不在" "brew の cask google-chrome が入るまで switch を確認（homebrew-base に宣言済み）"
fi

# 3. NoviSteps cookie — 無くても盤面は動く（novisteps パネルのみ stale）
if /usr/bin/security find-generic-password -s "$NOVI_KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
    ok "NoviSteps cookie (Keychain)"
else
    bad "NoviSteps cookie が Keychain に無い" \
        "Chrome で NoviSteps にログイン → DevTools で auth_session cookie をコピー → security add-generic-password -s $NOVI_KEYCHAIN_SERVICE -a \$USER -T /usr/bin/security -w '<cookie値>'"
fi

# 3b. AtCoder cookie — stopwatch の凍結検出用（無くても公開データは描画される）
if /usr/bin/security find-generic-password -s "atcoder-revel-session" -w >/dev/null 2>&1; then
    ok "AtCoder REVEL_SESSION (Keychain)"
else
    bad "AtCoder REVEL_SESSION が Keychain に無い（stopwatch 用・盤面自体は動く）" \
        "cp-login を実行（DevTools → Cookies → atcoder.jp → REVEL_SESSION。有効 ~6ヶ月）"
fi

# 4. ビルド成果物 — activation の swift ビルドが通ったか
missing=""
for b in set-wallpaper cp-dash-live; do
    [ -x "$ROOT/bin/$b" ] || missing="$missing $b"
done
[ -d "$HOME/Library/Screen Savers/CPDashSaver.saver" ] || missing="$missing CPDashSaver.saver"
if [ -z "$missing" ]; then
    ok "Swift ビルド成果物 3本"
else
    bad "ビルド成果物 不足:$missing" "CLT を入れて再 switch（#1 参照）"
fi

# 5. CPDashSaver の選択 — Tahoe は System Settings UI でしか選べない
if grep -qa CPDashSaver "$WALL_STORE" 2>/dev/null; then
    ok "CPDashSaver 選択済み"
else
    bad "CPDashSaver 未選択" \
        "System Settings → Wallpaper → Screen Saver… → Custom → Other → CPDashSaver（4クリック・自動化不可）"
fi

# 6. コンテナ symlink — saver は sandbox 内 HOME の cp-dash/wall.png を読む
lnk_missing=""
for c in com.apple.ScreenSaver.Engine.legacyScreenSaver com.apple.wallpaper.extension.legacy; do
    [ -L "$HOME/Library/Containers/$c/Data/cp-dash/wall.png" ] || lnk_missing="$lnk_missing $c"
done
if [ -z "$lnk_missing" ]; then
    ok "container symlink 2本"
else
    bad "container symlink 不足:$lnk_missing" \
        "ターミナルから: for c in com.apple.ScreenSaver.Engine.legacyScreenSaver com.apple.wallpaper.extension.legacy; do mkdir -p ~/Library/Containers/\$c/Data/cp-dash && ln -sf $ROOT/out/wall-main.png ~/Library/Containers/\$c/Data/cp-dash/wall.png; done"
fi

# 7. launchd 3本 — activation 直後は未ロードのこともある（再ログインで揃う）
loaded=$(/bin/launchctl list 2>/dev/null | grep -c "com\.treo\.cp-dashboard" || true)
if [ "$loaded" -ge 3 ]; then
    ok "launchd agents ${loaded}/3"
else
    meh "launchd agents ${loaded}/3 — activation 直後なら正常。再ログイン後にまだ欠けるなら launchctl list | grep cp-dashboard で調査"
fi

# 8. 実運転 — 直近サイクルの鮮度（40分以内に cycle done があるか）
if [ -f "$ROOT/out/update.log" ]; then
    last_done=$(grep "cycle done" "$ROOT/out/update.log" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
    if [ -n "$last_done" ]; then
        last_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_done" +%s 2>/dev/null || echo 0)
        age=$(( $(date +%s) - last_epoch ))
        if [ "$age" -lt 2400 ]; then
            ok "実運転（最終サイクル ${age}秒前）"
        else
            meh "最終サイクルが $((age/60)) 分前 — launchctl kickstart gui/\$UID/org.nix-community.home.com.treo.cp-dashboard で手動確認"
        fi
    else
        meh "update.log に完了サイクルなし — 初回機なら RunAtLoad 待ち"
    fi
else
    meh "update.log 未生成 — 初回機なら RunAtLoad 待ち（数分後に再実行）"
fi

exit 0
