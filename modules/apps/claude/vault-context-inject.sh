#!/bin/sh
# Claude Code SessionStart hook: auto-memory の代替となる個人文脈の自動注入。
# claude-obsidian vault の entry-map（scripts/entry-map.py・frontmatter からの
# 機械生成）を全プロジェクトのセッション冒頭に注入する。記憶の正史は vault
# （グローバル CLAUDE.md 参照）、締切の正史は Google カレンダー。
#
# 2026-09-11 改訂：hot.md（手書きの共有キャッシュ）の注入をやめた。
# hot.md は肥大2回（22k tok / 19,878字）・並列セッションで 1:n 化・一部締切の
# 唯一の所在地化、を受けて vault 側で廃止済み。生成物の entry-map は状態を
# 持たないので、サイズガード（旧 HOT_LIMIT）も不要になった——生成コードに
# 上限が入っている。
#
# - CLAUDE_NO_PERSONAL_CONTEXT=1 で完全に黙る（入れ子の claude -p 呼び出し
#   ——herdr-auto-name の haiku ラベル生成など——に個人文脈を食わせないための栓）。
# - claude-obsidian 内では entry-map を注入しない（プロジェクト側 hook が注入済み）。
#   inbox 計数だけ出す（triage できる場所でこそ見えるべきなので）。
# - vault が無い機体（seed 未運搬の新 Mac 等）では無音 no-op
# - 止めたいときは ~/.claude/settings.json の登録1行を消す（このファイルは nix 管理）

set -eu

[ -z "${CLAUDE_NO_PERSONAL_CONTEXT:-}" ] || exit 0

VAULT_ROOT="$HOME/Forge/claude-obsidian"
ENTRY_MAP="$VAULT_ROOT/scripts/entry-map.py"
INBOX="$VAULT_ROOT/vault/.raw/inbox"

[ -d "$VAULT_ROOT/vault/wiki" ] || exit 0

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

command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$ENTRY_MAP" ] || exit 0

echo "<personal-context source=\"claude-obsidian entry-map（機械生成）\">"
echo "個人文脈の入口（詳細が要るときだけ $VAULT_ROOT/vault/wiki/index.md → 個別ページへ。締切の正史は Google カレンダー）："
echo
python3 "$ENTRY_MAP" 2>/dev/null || true
echo
inbox_notice
echo "</personal-context>"
