#!/bin/sh
# Claude Code の SessionStart hook。herdr の pane 内で起動したときだけ、
# 現在の workspace/tab ラベルを添えて「テーマが見えたら日本語に rename せよ」
# という指示をセッション文脈に注入する。herdr 外では HERDR_ENV が無いので
# 無音の no-op（= herdr をやめれば挙動ごと消える。紐付けの本体はこのゲート）。
#
# 管理元: nix-darwin-conf/home/herdr.nix（~/.claude/hooks/ 側は nix store への
# symlink なので直接編集しない）。純正 integration hook（herdr-agent-state.sh、
# 「custom hooks は隣に置け」方式）と同じゲート構造に揃えている。

set -eu

# hook は stdin に JSON を受けるが本 hook では使わない（読み捨て）
cat >/dev/null 2>&1 || true

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_WORKSPACE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

ws_json="$(herdr workspace get "$HERDR_WORKSPACE_ID" 2>/dev/null)" || exit 0
tab_json=""
if [ -n "${HERDR_TAB_ID:-}" ]; then
  tab_json="$(herdr tab get "$HERDR_TAB_ID" 2>/dev/null)" || tab_json=""
fi

WS_JSON="$ws_json" TAB_JSON="$tab_json" python3 - <<'PY'
import json
import os

try:
    ws = json.loads(os.environ["WS_JSON"])["result"]["workspace"]
except Exception:
    raise SystemExit(0)

tab_label = ""
try:
    tab_label = json.loads(os.environ.get("TAB_JSON") or "{}")["result"]["tab"].get("label", "")
except Exception:
    pass

ws_id = os.environ.get("HERDR_WORKSPACE_ID", "")
tab_id = os.environ.get("HERDR_TAB_ID", "")
ws_label = ws.get("label", "")

print(f"""<herdr-auto-name>
このセッションは herdr の workspace {ws_id}（現ラベル:「{ws_label}」）/ tab {tab_id}（現ラベル:「{tab_label}」）の中で動いている。
現ラベルが汎用名（ディレクトリ名・数字・agent 名など）のままなら、このセッションの作業テーマが明確になった時点で一度だけ、短い日本語ラベルに改名すること:
  herdr workspace rename {ws_id} "<作業テーマ（日本語・10文字前後）>"
  herdr tab rename {tab_id} "<タスク名（日本語・10文字前後）>"
既に意味のあるラベルが付いている場合や、テーマがまだ不明瞭なうちは改名しない。改名の実行は報告不要（黙って行ってよい）。セッション途中でテーマが大きく変わったら改名し直してよい。
</herdr-auto-name>""")
PY
