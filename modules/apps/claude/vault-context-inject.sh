#!/bin/sh
# Claude Code SessionStart hook: auto-memory の代替となる個人文脈の自動注入。
# claude-obsidian vault の hot.md（直近文脈・約500語）を全プロジェクトの
# セッション冒頭に注入する。記憶の正史は vault（グローバル CLAUDE.md 参照）。
#
# - claude-obsidian 自身の中では no-op（プロジェクト側 SessionStart hook が注入済み）
# - vault が無い機体（seed 未運搬の新 Mac 等）では無音 no-op
# - 止めたいときは ~/.claude/settings.json の登録1行を消す（このファイルは nix 管理）

set -eu

VAULT_ROOT="$HOME/Forge/claude-obsidian"
HOT="$VAULT_ROOT/vault/wiki/hot.md"

[ -r "$HOT" ] || exit 0

case "$(pwd)" in
  "$VAULT_ROOT"*) exit 0 ;;
esac

echo "<personal-context source=\"claude-obsidian vault/wiki/hot.md\">"
echo "個人文脈の hot cache（正史は vault。詳細が要るときだけ $VAULT_ROOT/vault/wiki/index.md → 個別ページへ）："
echo
cat "$HOT"
echo "</personal-context>"
