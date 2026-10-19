---
name: space-rename
description: herdr の workspace / tab（ユーザーの言う「space」）を、今の会話内容に合った日本語ラベルに付け替える。ラベルを指定されたらそれを使い、無ければ会話から 10 文字前後で自分で決める。Use when the user says "/space-rename", "space の名前を変えて", "space 改名", "ワークスペース名", "rename workspace", "space 一覧", "いま何の space", or hands you a label to set.
---

# space-rename — herdr workspace / tab の手動命名

**自動命名との分担**：自動命名は `~/.claude/hooks/herdr-auto-name.sh`（UserPromptSubmit hook）が
5 発話ごとに haiku で行う。ただし **ラベルが herdr の既定値（workspace = cwd の basename、
tab = 数字）のまま** のときだけ動く。このスキルで付けた名前は既定値と一致しないので
自動命名に上書きされない。手動で付け直したあと自動に戻したいなら、既定値
（cwd の basename）に rename し直せば次の 5 発話目で再挑戦する。

## 手順

1. **herdr の中か確認**。`printenv HERDR_WORKSPACE_ID HERDR_TAB_ID` で両方取れなければ
   「herdr の外なので space は無い」と一行で返して終わる。
2. **ラベルを決める**。
   - ユーザーがラベルを渡していればそのまま使う（空白ありでも可。herdr は複数語を受ける）。
   - 渡されていなければ会話から自分で決める：**日本語・10 文字前後・引用符や記号装飾なし**。
     workspace ラベル＝セッション全体のテーマ、tab ラベル＝直近で取り組んでいる作業。
     tab が 1 つしか無い／区別が要らないなら両方同じでよい。
   - 迷っても AskUserQuestion は使わない（名前は後からいくらでも変えられる）。
3. **rename する**（両方とも id は env から）：

   ```sh
   herdr workspace rename "$HERDR_WORKSPACE_ID" "<workspace ラベル>"
   herdr tab rename "$HERDR_TAB_ID" "<tab ラベル>"
   ```

4. **確認**：`herdr workspace get "$HERDR_WORKSPACE_ID"` の `result.workspace.label` が
   新ラベルになっていることを見る。
5. **報告は一行**：「space を『◯◯』（tab『△△』）に改名した」だけ。前後の説明は要らない。

## 一覧を聞かれたとき（"space 一覧" / "いま何の space"）

`herdr workspace list` を叩き、`number`・`label`・`agent_status`・`workspace_id` を
番号順の短い表で出す。現在の workspace（`focused: true`）に印を付ける。

## 注意

- `herdr workspace rename` / `herdr tab rename` は socket API で即時反映。undo は無いが、
  もう一度 rename すれば戻る（破壊的ではない）。
- 他人の workspace（自分の `HERDR_WORKSPACE_ID` 以外）は、ユーザーが id か番号を明示したとき
  だけ触る。
- 管理元は nix-darwin-conf `modules/apps/claude/skills/space-rename/`（`~/.claude/skills/` 側は
  nix store への symlink なので直接編集しない）。
