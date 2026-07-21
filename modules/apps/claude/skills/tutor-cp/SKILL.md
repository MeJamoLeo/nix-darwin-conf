---
name: tutor-cp
description: >
  tutor の CP（競技プログラミング・AtCoder）拡張モジュール。問題ディレクトリの推論
  （URL→DIR、ABC/ARC/AGC 同時開催補正）・素材ロード・cp-guide（未 AC の段階学習）・
  cp-review（AC 後の calibration レビュー）を持つ。正本メモリは vault の
  learning-competitive。必ず tutor スキル（コア）を先に読み、その作法（ペルソナ・
  ソクラテス減衰・書き戻し手順）に従う。
  Triggers on: "cp-guide", "cp-review", "AtCoder", "ABC", "この問題を教えて",
  "精進", "コンテストの復習", "/tutor-cp".
allowed-tools: Read Write Edit Glob Grep Bash WebFetch WebSearch
---

# tutor-cp — CP 拡張（AtCoder 専用 2 モード）

**前提：まず `~/.claude/skills/tutor/SKILL.md`（コア版）を Read し、そのペルソナ・
起動時の必須行動（learner-profile と retrieve.py の prior 読み込み）・ソクラテス減衰・
禁止事項・書き戻し手順に従う。** 本スキルは CP 特有の入力解決と 2 モードだけを足す層。

## 環境（マシン非依存の約束事）

- 問題ディレクトリ：`$HOME/cp/contests/<contest>/<problem>/`（x1nano も Mac も `~/cp`）。
- `cp-go` ツールは PATH 上（x1nano=`~/nixos-cp/tools/cp-go`／Mac=`~/bin/cp-go`。
  Mac は AeroSpace `alt-g`→`cp-go-launch` で起動＝vault の [[cp-go-macos-port]] 参照）。
- **CP の正本メモリは vault の `learning-competitive.md`**（`$VAULT/wiki/` 配下、
  retrieve.py で該当 📗 KB アトム＋L1 該当エントリだけ引く。**全文 Read 不可**——
  90k トークン級に肥大している）。

## 入力解決（ディレクトリ推論）

`cp-guide` / `cp-review` の引数は URL・問題ディレクトリ・省略（=cwd）のいずれでもよい：

1. **省略** → cwd が `~/cp/contests/<contest>/<problem>/` 形ならそれを使う。違えば訊く。
2. **URL**（例 `https://atcoder.jp/contests/abc412/tasks/abc412_d`）→
   `~/cp/contests/<contest>/<problem>/` に対応付ける。**ABC/ARC/AGC 同時開催補正**
   （同一問題が複数コンテストに載る場合）は cp-go のロジックに合わせる：既存ディレクトリを
   `ls ~/cp/contests/` で確認し、実在する側を採用。どちらも無ければ問題側の contest を使う。
3. **ディレクトリ** → そのまま。存在しなければ訊く（勝手に mkdir しない）。

素材ロード：問題本文（WebFetch）＋ `main.py` ＋ sample I/O 1ペア。`main.py` が空でも続行。

## cp-guide [URL or DIR or 省略] — 未 AC（WIP/WA/TLE どれでも）

薄い wrapper。入力解決 → 素材ロード → **tutor コアの guide モードに委譲**
（プラン設計・Step 解説・1ステップずつのソクラテス対話は guide 本体の責務）。
learner-profile の Learning Style（1問ずつ短く・具体例で）を厳守。

## cp-review [URL or DIR or 省略] — AC 後の calibration レビュー

WA/TLE デバッグは対象外（それは cp-guide）。

1. 素材ロード＋過去の idiom を `python3 $VAULT_REPO/scripts/retrieve.py "<idiom>"` で検索
   （該当 📗 KB アトム＋ L1 該当エントリだけ Read）。
2. **10段階評価**。軸＝「学習者の現在の idiom レパートリーに照らした calibration 余地」。
   正しさ・計算量は原則対象外。評価は数字と根拠で（過大評価インフレ禁止）。
3. 満点 → learning-competitive に「解いた問題」1行追記で即終了。
   満点未満 → mini ソクラテス thread（1-3 候補・named idiom 提示・「今はいい」で即引く）。
4. **書き戻しは tutor コアの手順に従う**（lock → 書く → release → commit）：
   - learning-competitive に L1 append（時系列）
   - 📗 KB アトムを create-or-update ＋ `grasp:` 更新
   - 正本=vault。索引は次回 claude-obsidian セッションの catch-up が自動
5. memory feedback を適用：review 温度は抑えめ・初遭遇の idiom は深掘りしない・
   constructor 選好を尊重・ソクラテス徹底。

## 境界

- grill 系（plan grill）は取り込まない（vault に既存の grill 系がある）。
- vault への書き込みは tutor コアの書き戻し手順のみ。learning-competitive の全文 Read 禁止。
- claude-obsidian セッション内で CP を扱う場合は project 版 tutor の CP モードが優先
  （作法は同一。divergence したら project 版が正）。
