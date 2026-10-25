---
name: course
description: 授業の課題に着手できる状態まで環境を整える。文脈とシラバスを確認し、Canvas の一次資料が Store に揃っているかを突き合わせ、足りない物を保存し、やることを作業単位に割る。答えが存在する課題はサンプル解答を1枚作って置いておき（毎回 AI に訊かなくて済む状態にする）、答えが無い課題は「どう作るか」の手順を TODO に落とす。提出はしない。Triggers on "/course", "課題", "宿題", "assignment", "zylab", "exercise", "レポート", "着手", or a course code such as CS4355 / CS4371 / CS2315 / CS3360.
---

# course — 授業の作業環境を整える

**やること**：着手の準備。資料を揃え、作業単位に割り、始められる状態にして渡す。
**やらないこと**：提出（Gradescope / Canvas / zyBook への投稿は本人の手番）。
解き方を教えること（→ `tutor` / `tutor-cp`）。課題を本人の代わりに解き切ること。

---

## 0. 前提：Canvas トークン

Canvas を叩く前に、トークンが取れるか確認する。経路は Keychain（`canvas-txst-token`）が
主で、無いときだけ rbw にフォールバックする。**rbw がロックされていたら `rbw unlock` は
本人の手番**（パスフレーズ入力は人間に残す2種のうちの1つ）。unlock を頼むときは
`rbw unlock` の1行だけ出す。解錠は 8 時間保つので、1セッションに1回で足りる。

**トークンの値を stdout に出さない。** 下の経路は内部で取得して使うので、値が
コンテキストにも transcript にも載らない（`deny-secret-reads` hook が守っている領域）。

## 1. コンテキストを確認する

| 欲しい物 | 正本 | 取り方 |
|---|---|---|
| 締切 | **Google カレンダー** | `mcp__claude_ai_Google_Calendar__list_events` / `search_events` |
| 未処理の課題・今日の割り当て | **todo-board** | `todo`（ogasawara 本体。tanegashima は SSH ラッパ） |
| 過去の経緯・設計判断 | **vault**（`/Users/treo/Forge/claude-obsidian`） | entry-map → `vault/wiki/index.md` → 個別ページ |

必要な分だけ読む。**全部を毎回読まない。** vault は worktree の中にいても本体を読む。

## 2. シラバスを確認する

配点・提出先・遅延規定の一次情報。`~/Store/20_Courses/<COURSE>/` 直下の
`*[Ss]yllabus*.pdf` を見る。**Store に無ければ Canvas の `/files` にある**ことが多いので
§3 で拾って §4 で保存する（2026-10-25 時点、CS4371 のシラバスが Canvas にだけあった）。

## 3. Canvas の一次資料が揃っているか見る

科目の実在と active かどうかは **Canvas が正本**（Store のディレクトリは資料が来てから
作られるので、Store に無い＝履修していない、ではない）。

```sh
python3 -c "
import sys, os; sys.path.insert(0, os.path.expanduser('~/.local/lib/todo-board'))
from todo_board import canvas
for c in canvas.http_get_json('/courses?enrollment_state=active&per_page=50'):
    print(c['id'], c.get('course_code') or c.get('name'))
"
```

同じ `canvas.http_get_json` で、コース ID を当ててから：

- `/courses/<id>/assignments?per_page=100` — 課題（`name` / `due_at` / `description` /
  `submission_types` / `points_possible`）
- `/courses/<id>/files?per_page=100` — 配布ファイル（`display_name` / `url` / `updated_at`）
- `/courses/<id>/modules?per_page=100` — 使っていないコースでは空で返る

**突き合わせ**：`/files` の `display_name` と `~/Store/20_Courses/<COURSE>/` 配下の
ファイル名を比べ、**Store に無い物だけ**を落とす対象にする。既にある物は落とし直さない
（再取得は二重化の入口）。

## 4. 足りない一次資料を Store に保存する

- 置き場は `~/Store/20_Courses/<COURSE>/`。2段目から下は `~/Store/README.md` の
  「サブフォルダの作り方」に従う（1段に1つの問い・深さ4段まで・**中身が来てから作る**）。
- **ファイル名は Canvas の `display_name` のまま**にする。改名すると次回の突き合わせで
  同じ物をもう一度落とすことになる。
- `files` の `url` は署名済みなので、追加の認証なしに取得できる。
- 落としたら何をどこに置いたかを1行で報告する（長い一覧にしない）。

## 5. 必要なことを作業単位に割る

課題1件＝1タスクにしない。**「次に手を動かせる単位」**まで割る。割った結果の置き場は
**todo-board 一本**にする（`todo add "<項目>" --due "M/D HH:MM" --size 1.5h`）。
**日付は `M/D` 形式**——`YYYY-MM-DD` は `bad date` で弾かれる（2026-10-25 に実測）。
★ 別ファイルに作業リストを作らない——リストが2つあると必ず乖離する。

割ったら §6 で課題の性質に応じて枝分かれする。

## 6. 答えがあるか無いかで分ける

### 6a. 答えが存在する課題（教科書の演習・zyLab・解答例が出る物）

**サンプル解答を1枚作って置いておく。** 目的は「毎回 AI に訊かなくていい状態にする」こと。

- 置き場は課題ディレクトリ直下の **`ai-reference.md`**（Store 規則4＝段を足さず名前で区別）。
- 冒頭に必ずこの3行を書く：
  - `AI 生成の参考解答。提出物ではない。`
  - 生成日と、何を見て作ったか（教科書の章・配布ファイル名）
  - 検証したかどうか（zyLab なら `zyg++` に通したか。通していないなら「未検証」と明記）
- **本人の答案と同じ名前にしない・上書きしない。** 答案は本人のファイルに書く。
- 解き筋だけでなく「なぜその手が出るか」を1〜2行添える。後から読むのは本人で、
  そのとき欲しいのは答えではなく**再現できる手順**だから。

### 6b. 答えが無い課題（レポート・設計・プレゼン・自作物）

**成果物の作り方を手順に落とす。** 答えが無いので、代わりに「どう進めれば完成するか」を
作業単位に割って `todo add` する。1項目＝30〜90分で終わる粒度にする。

典型の割り方（課題に合わせて組み替える）：資料を読む → 主張/方針を1文で決める →
骨組み（見出しだけ）→ 各節を埋める → 自己レビュー（rubric と突き合わせ）→ 清書。

rubric がシラバスか Canvas の課題説明にあるなら、**割った項目に rubric の配点を紐づける**。
配点の無い所に時間を使わないため。

## 7. 渡して終わる

**短く**これだけ出す。長い計画書にしない（一括レビュー型は使われなくなる）。

1. 締切（日付と、残り時間の体感）
2. 揃えた物 / 落とした物（パス 1〜3件）
3. 使う道具のコマンド1行
4. 最初の一手

## 道具（nix が配っている）

- **zyLab（CS4355）** — `zyg++` が zyLab 相当の g++ + 警告フル。手元の検証はこれ。
  `ZYG_SAN=1 zyg++` は ASan/UBSan 版（探索用）。clangd 用の `compile_commands.json` は
  switch 時に**既存の** zylab ディレクトリにだけ撒かれるので、新しく切ったら `nhds`。
- **手書きを PDF 1本に束ねる** — `<課題>/scans/` に画像を置いて `ex-pdf <exNN>`。
- **紙に出す** — `python3 /Users/treo/Forge/claude-obsidian/bin/campus-print.py`。
- **Claude が作る物は Markdown。docx / xlsx / pptx は作らない**（本人指定）。
  Word が要る物は本人が Word / Teams 側で作る。こちらは貼り付け用の Markdown まで。

## 作業場

既定は **`~/Store/20_Courses/<COURSE>/` で直接**。worktree を作らない。
独立した git repo のコード課題を並列で試すときだけ Orca worktree を使う
（`CS3360/assignment3`・`CS4371/project2/src` は Orca 登録済み）。
vault を書き換えるなら vault 本体 checkout（worktree だと `wiki-lock` が別物になる）。

★ **Store は正本が1箇所しかない。worktree 化＝複製＝乖離。**
