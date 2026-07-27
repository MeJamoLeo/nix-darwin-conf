#!/bin/bash
# caldash 健診（腐らない手順書）。switch のたびに ✗ と初回ログイン手順を表示する。
root="${1:-$HOME/calendar-dashboard}"
uid="$(id -u)"
label="org.nix-community.home.com.treo.calendar-dashboard-live"
ok(){ printf "  \033[32m✓\033[0m %s\n" "$1"; }
ng(){ printf "  \033[31m✗\033[0m %s\n       → %s\n" "$1" "$2"; }

echo "── caldash doctor ──────────────────────────────"
if /usr/bin/xcrun -f swiftc >/dev/null 2>&1; then ok "CLT/swiftc あり"; else ng "CLT/swiftc 不在" "xcode-select --install 後に再 switch"; fi
if [ -x "$root/bin/caldash-live" ]; then ok "caldash-live ビルド済"; else ng "caldash-live 未ビルド" "CLT を入れて再 switch"; fi
if /bin/launchctl print "gui/$uid/$label" >/dev/null 2>&1; then ok "launchd agent ロード済"; else ng "launchd agent 未ロード" "再 switch で張り直し"; fi

cat <<EOF
  ℹ 初回のみ手動ログインが必要（Claude/自動は資格情報を入力しない）:
     1) $root/bin/caldash-live           # 通常窓が開く（--wallpaper 無し）
     2) 4面のどれか1面で Google にログイン
     3) ⌘Q で閉じる → launchd の --wallpaper 常駐が以後ログイン済みで起つ
     比率変更: $root/caldash-config.json の cols/rows を編集 → 常駐を再起動
       launchctl kickstart -k gui/$uid/$label
────────────────────────────────────────────────
EOF
