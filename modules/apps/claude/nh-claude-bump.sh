#!/usr/bin/env bash
# nh ラッパの本体。modules/apps/claude/home.nix が writeShellScriptBin "nh" の
# 末尾にこのファイルを readFile で埋め込む（＝PATH 上の `nh` はこれになる）。
#
# 役割：`nh darwin switch` のたびに claude-code の input だけを bump して、
# ビルドが通ったら flake.lock を commit する（push はしない）。
#
# nix 側が先に定義する変数：
#   NH_REAL            本物の nh のフルパス
#   CLAUDE_FLAKE_DIR   この nix-darwin-conf の作業ツリー
#   CLAUDE_INPUT       bump する flake input 名（nixpkgs-claude）
#   PATH               nix / git / jq を含む
#
# 1行目の shebang は埋め込み時には単なるコメントになる（単体で shellcheck を
# かけたいので残してある）。

set -u

# claude-code の鮮度と関係ない呼び出し（nh clean / nh home / nh search …）は素通し。
# ここで exec して抜けるので、週次の launchd clean は一切影響を受けない。
case "${1-}:${2-}" in
darwin:switch | darwin:build) ;;
*) exec "$NH_REAL" "$@" ;;
esac

lock="$CLAUDE_FLAKE_DIR/flake.lock"

locked_rev() {
  jq -r --arg n "$CLAUDE_INPUT" '.nodes[$n].locked.rev // ""' "$lock" 2>/dev/null
}

# flake.lock が「bump する前から汚れていたか」を先に見る。汚れていたら commit は
# 見送る——flake.lock は1ファイルなので、部分 commit では他の input の bump を
# 分離できず、"chore(claude-code)" という嘘のメッセージで巻き込むことになる。
lock_was_clean=0
if git -C "$CLAUDE_FLAKE_DIR" diff --quiet HEAD -- flake.lock 2>/dev/null; then
  lock_was_clean=1
fi

before="$(locked_rev)"
if ! nix flake update "$CLAUDE_INPUT" --flake "$CLAUDE_FLAKE_DIR"; then
  echo "nh(claude-bump): $CLAUDE_INPUT の更新に失敗した（オフライン？）。今の flake.lock のまま続行する。" >&2
fi
after="$(locked_rev)"

"$NH_REAL" "$@"
rc=$?

if [ "$rc" -eq 0 ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
  if [ "$lock_was_clean" -eq 1 ]; then
    if git -C "$CLAUDE_FLAKE_DIR" commit --quiet \
      -m "chore(claude-code): $CLAUDE_INPUT を bump（${before:0:7} → ${after:0:7}）" \
      -- flake.lock; then
      echo "nh(claude-bump): flake.lock を commit した（push はしない）。他機体へは手で push する。" >&2
    else
      echo "nh(claude-bump): flake.lock の commit に失敗した（署名鍵？）。git status を見て。" >&2
    fi
  else
    echo "nh(claude-bump): flake.lock に別の未コミット変更があるので commit は見送った。" >&2
  fi
fi

exit $rc
