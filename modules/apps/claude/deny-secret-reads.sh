#!/usr/bin/env bash
# PreToolUse(Bash) hook — 秘密の「平文を stdout に出すコマンド」を機械的に拒否する。
#
# なぜ必要か（2026-09-04 の実例）:
#   Claude が Bitwarden アイテムの構造を見るのに `rbw get --full <name> | cut -d: -f1`
#   を実行した。`--full` は1行目にパスワードを出す仕様なので、campus password
#   （TXST の identity 全体を開く鍵）が丸ごとモデルのコンテキストと transcript に載った。
#   CLAUDE.md への「気をつける」系の記述では止まらない——事故は判断ではなく
#   うっかりで起きるので、検知は自動経路に置く（hot.md 肥大検知と同じ構図）。
#
# 設計:
#   - コマンド文字列**全体**に対して正規表現を当てる。permissions.deny は前方一致
#     なので `foo | rbw get x` や `sh -c "rbw get x"` をすり抜けるが、こちらは拾う。
#   - エージェントが秘密の平文を見る必要は原則ゼロ。秘密を要るのは
#     「秘密を消費するプロセス」であって、そのプロセスが自分で読めばよい
#     （例: bin/campus-print.py は自分で Keychain を叩く）。
#   - 存在確認・健全性チェックは値を出さない経路で足りる:
#       rbw list / rbw get <name> >/dev/null 2>&1 の終了コード /
#       security find-generic-password -s <svc> （-w も -g も付けない）
#
# 限界（正直に書く）:
#   これは**事故止め**であって敵対的サンドボックスではない。base64 経由・python の
#   ctypes・自作ラッパ等でいくらでも回避できる。狙いは「うっかり平文を出す」を
#   ゼロにすることで、悪意ある回避を防ぐことではない。
#
# 解除:
#   ~/.claude/settings.json の PreToolUse から本フックの登録行を外す。
#   一時的に緩めるなら permissionDecision を "deny" → "ask" に変える（下部）。

set -uo pipefail

DECISION="deny" # "ask" にすると拒否ではなく都度確認になる

payload="$(cat)"

extract_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c \
      'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' \
      2>/dev/null && return 0
  fi
  return 1
}

cmd="$(extract_command)" || {
  # パーサが無い＝判定不能。ここで全部拒否すると Bash が使えなくなるので通すが、
  # 黙って通すと「効いているつもり」になるのでユーザーには見せる。
  printf '{"systemMessage":"deny-secret-reads: jq も python3 も無く判定できませんでした（このコマンドは検査されていません）"}\n'
  exit 0
}

[ -n "$cmd" ] || exit 0

deny() {
  # jq があれば理由を安全にエスケープする。無ければ引用符を潰した素の文字列で出す。
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg d "$DECISION" --arg r "$1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
      "$DECISION" "$(printf '%s' "$1" | tr -d '"\\')"
  fi
  exit 0
}

# 語の直前が「識別子の一部ではない」ことを要求する接頭辞。`grep-rbw` のような
# 別コマンドに誤爆せず、`| rbw` や `$(rbw` や `sh -c "rbw` は拾う。
B='(^|[^A-Za-z0-9_./-])'

# シェルのメタ文字を空白に潰した正規化版に対して照合する。
# こうしないと `a=$(security ... -w)` のように**閉じ括弧が語の直後に来る形**を
# 取りこぼす（実測でこの形だけすり抜けた）。報告用には元の $cmd を使う。
norm="$(printf '%s' "$cmd" | tr '();|&`"'"'"'\n\t' ' ')"

has() { printf '%s' "$norm" | grep -Eq "$1"; }

# --- Tier 1: シークレットマネージャの値取り出し（誤爆ほぼ無し） ---
if has "${B}rbw[[:space:]]+(get|code)([[:space:]]|$)"; then
  deny "rbw get/code は秘密の平文を stdout に出すため禁止（2026-09-04 に campus password をコンテキストに載せた事故の再発防止）。存在確認は 'rbw list' か 'rbw get <name> >/dev/null 2>&1' の終了コードを使うこと。値が必要な処理は、値を消費するスクリプト自身に読ませる。人間が値を見たい場合はユーザー自身が端末で実行する。"
fi

if has "${B}bw[[:space:]]+(get|list)([[:space:]]|$)"; then
  deny "公式 Bitwarden CLI (bw) の get/list は秘密を JSON ごと出しうるため禁止。理由と代替は rbw と同じ。"
fi

# security(1) は -w / -g を付けたときだけ値を出す。付けない形（存在確認・属性表示）は許可。
if has "security[[:space:]]+find-(generic|internet)-password" && has "[[:space:]]-(w|g)([[:space:]]|$)"; then
  deny "security find-*-password の -w / -g は Keychain の平文を出すため禁止。存在確認は -w を付けずに実行するか、'security find-generic-password -s <svc> >/dev/null 2>&1' の終了コードを見ること。値が必要な処理は、値を消費するスクリプト自身に読ませる。"
fi

if has "${B}pass[[:space:]]+show([[:space:]]|$)"; then
  deny "pass show は秘密の平文を出すため禁止。"
fi

if has "${B}op[[:space:]]+(read|item[[:space:]]+get)([[:space:]]|$)"; then
  deny "1Password CLI の op read / op item get は秘密の平文を出すため禁止。"
fi

# --- Tier 2: 資格情報ファイルの読み出し ---
READERS='(cat|bat|less|more|head|tail|strings|xxd|od|nl|cut|awk|sed|rg|grep)'
SECRET_FILES='(/\.aws/credentials|/\.netrc|/\.pgpass|/\.npmrc|/\.pypirc|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.pem([[:space:]]|$)|\.p12([[:space:]]|$)|service-account[^ ]*\.json|credentials\.json)'
if has "${B}${READERS}[[:space:]][^ ]*${SECRET_FILES}"; then
  deny "秘密鍵・資格情報ファイルの内容表示は禁止。存在確認は 'ls' や 'test -f' を使うこと。"
fi

# .env は .env.example / .env.sample / .env.template を除いて拒否する。
if has "${B}${READERS}[[:space:]][^ ]*\.env([[:space:]]|$|[^a-zA-Z.])" \
  && ! has "\.env\.(example|sample|template|dist)"; then
  deny ".env の内容表示は禁止（実値が入っている前提で扱う）。変数名だけ要るなら 'grep -o \"^[A-Z_]*=\" .env' のように値を落として取ること。"
fi

exit 0
