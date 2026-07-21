#!/bin/sh
# Claude Code SessionStart hook: auto-memory の代替となる個人文脈の自動注入。
# claude-obsidian vault の hot.md（直近文脈・約500語）を全プロジェクトの
# セッション冒頭に注入する。記憶の正史は vault（グローバル CLAUDE.md 参照）。
#
# ガード2枚（「規律をコードに降ろす」cp-dashboard 教訓の適用）：
# - hot.md サイズ上限：500語規律が破れて肥大した場合（前科＝2026-07-05 の 22k
#   トークン事故）、全プロジェクトへ被害を増幅しないよう先頭だけ注入して騒ぐ。
# - inbox 計数：triage（inbox→wiki ページ化）は claude-obsidian セッションでしか
#   走らないため、未処理の溜まりをどこからでも見えるようにする。
#
# - claude-obsidian 内では hot.md は注入しない（プロジェクト側 hook が注入済み）。
#   inbox 計数だけ出す（triage できる場所でこそ見えるべきなので）。
# - vault が無い機体（seed 未運搬の新 Mac 等）では無音 no-op
# - 止めたいときは ~/.claude/settings.json の登録1行を消す（このファイルは nix 管理）

set -eu

VAULT_ROOT="$HOME/Forge/claude-obsidian"
HOT="$VAULT_ROOT/vault/wiki/hot.md"
INBOX="$VAULT_ROOT/vault/.raw/inbox"
HOT_LIMIT=8192 # bytes。500語規律の健全域は ~5KB。超過＝規律が破れているサイン

[ -r "$HOT" ] || exit 0

in_vault=0
case "$(pwd)" in
  "$VAULT_ROOT"*) in_vault=1 ;;
esac

inbox_notice() {
  [ -d "$INBOX" ] || return 0
  n=$(find "$INBOX" -type f ! -name '.*' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || return 0
  echo "📥 vault/.raw/inbox に未処理 ${n} 件。記憶・保存系の話題が出たら claude-obsidian での triage を一言促すこと。"
}

if [ "$in_vault" -eq 1 ]; then
  inbox_notice
  exit 0
fi

echo "<personal-context source=\"claude-obsidian vault/wiki/hot.md\">"
echo "個人文脈の hot cache（正史は vault。詳細が要るときだけ $VAULT_ROOT/vault/wiki/index.md → 個別ページへ）："
echo

hot_size=$(wc -c <"$HOT" | tr -d ' ')
if [ "$hot_size" -gt "$HOT_LIMIT" ]; then
  echo "⚠️ hot.md が ${hot_size}B に肥大している（注入上限 ${HOT_LIMIT}B・完全上書き500語の規律が破れている）。先頭だけ注入する。ユーザーに claude-obsidian で hot.md を規律どおり書き直すよう伝えること。"
  echo
  head -c "$HOT_LIMIT" "$HOT"
  echo
  echo "…（肥大のため残り $((hot_size - HOT_LIMIT))B は切り捨て）"
else
  cat "$HOT"
fi

echo
inbox_notice
echo "</personal-context>"
