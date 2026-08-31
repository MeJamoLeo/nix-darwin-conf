{
  config,
  pkgs,
  ...
}: {
  # record-blocks — Claude Code の transcript から1日の作業ブロックを復元する。
  # 実装は ./bin/record-blocks（python3 1本）。仕組みと限界は script 冒頭 docstring を参照。
  #
  # なぜ custom バケツか（modules/CLAUDE.md 判定）:
  #   価値の中心が自分のコード（transcript の解釈・無活動での分割・gap 検出）で、
  #   Claude Code の設定ではない。apps/claude は Claude Code 本体の配線が仕事なので別。
  #
  # ★ 2026-08-30 の発端：Google カレンダー "Record" を後から埋めるとき、
  #   **終了時刻は git のコミットや mtime から拾えるのに開始時刻だけ復元できない**
  #   という非対称があった（実測：推定した開始時刻が1時間ずれていた／
  #   auto-commit の 14:21 は実際には 13:16 の編集をバッチで拾っただけだった）。
  #
  #   ★ 一般形＝**記録が無いと思ったら、まず既存のログに無いかを見る。**
  #     Claude Code は開始時刻も「きっかけ」も `ai-title` も既に残していた。
  #     足りなかったのは計測器ではなく読み出し経路。新しい常駐を足すより安い。
  #
  # ⚠ 先例＝`~/Forge/mac-study-tracker`（スクショ→解析→カレンダー）は自作したまま
  #   **2026-04-30 で死んでいる**（watermark が 4ヶ月前・screenshots に 468 枚が孤児・
  #   LaunchAgent 未登録・この repo にも入っていない）。同じ日の hot.md の教訓と同型で、
  #   **実行経路を人間の任意呼び出しに置くと回らない**。だから launchd に載せる。
  #
  # 取れないもの（設計上の限界。手入力のまま残る）:
  #   端末外の作業（ジム・食事・移動・ブラウザや Word だけで完結した作業）は映らない。
  #   出力の `gaps` がその候補として毎日出る。

  home.file."bin/record-blocks" = {
    source = ./bin/record-blocks;
    executable = true;
  };

  # 日次で前日分を JSON に落とす。
  #   ⚠ transcript は Claude Code の `cleanupPeriodDays`（既定 30 日）で消えるので、
  #     この JSON を毎日書いておくこと自体が保持期間の対策になっている。
  #   ⚠ python は PATH から探さない。launchd の PATH は最小で、`#!/usr/bin/env python3`
  #     は何を拾うか分からない（同じ罠を 2026-08-30 に bash 3.2 で踏んだ）。
  #     インタプリタを store パスで固定して渡す。
  #   ⚠ Mac が寝ていて 03:30 を跨いだ場合、launchd は起床後に取りこぼし分を1回走らせる。
  launchd.agents.record-blocks = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "${config.home.homeDirectory}/bin/record-blocks"
        "--date"
        "yesterday"
        "--out-dir"
        "${config.home.homeDirectory}/Library/RecordBlocks"
      ];
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 30;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/record-blocks.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/record-blocks.err.log";
    };
  };
}
