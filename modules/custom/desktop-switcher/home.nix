{
  config,
  pkgs,
  lib,
  ...
}: {
  # desktop-switcher — デスクトップ壁紙レイヤーの切替 dispatcher。
  # 実装は ./bin/desktop-switch（bash 1本）。仕組みは script 冒頭コメントを参照。
  # signal handler は各 dashboard（calendar-dashboard / cp/dashboard）の swift 側に同居する。
  #
  # なぜ custom バケツか（modules/CLAUDE.md 判定）:
  #   価値の中心が自分のコード（signal 配線・状態管理・reload シーケンス）で、
  #   既製品の設定ではない。cp/dashboard と calendar-dashboard を跨ぐ「切替」
  #   という単独の関心事なのでどちらの下でもなく独立モジュールが妥当。
  #
  # ★ 2026-08-30：AeroSpace → OmniWM 移行で**入口が手動から自動に変わった**。
  #   旧：aerospace の alt-0/1/2 が desktop-switch を exec-and-forget で叩く
  #   新：ディスプレイ構成が変わるたび OmniWM のイベントで desktop-auto が走る
  #
  #   反転の理由は OmniWM の構造的制約。**ホットキーに任意コマンドを実行する口が無い**
  #   （169個のコマンド ID を全列挙して exec 相当はゼロ）。skhd 等の外部ホットキー
  #   デーモンは導入しない判断をしたので、キー起動は諦めた。代わりに
  #   `omniwmctl watch --exec` が**イベント駆動の exec を持っていた**のでそちらへ移した。
  #   結果として「押して切り替える」から「構成に応じて勝手に決まる」に設計が変わっている。
  #   手動切替が要るときは `desktop-switch caldash` を端末から叩けば従来どおり効く。

  home.file."bin/desktop-switch" = {
    source = ./bin/desktop-switch;
    executable = true;
  };

  home.file."bin/desktop-auto" = {
    source = ./bin/desktop-auto;
    executable = true;
  };

  # ディスプレイ構成の変化を監視して desktop-auto を走らせる常駐。
  #   ⚠ OmniWM の IPC ソケットが立つ前に起きると omniwmctl が接続に失敗するので、
  #     KeepAlive で落ちても復活させる（初回ログイン時の起動競合はこれで吸収する）。
  #   ⚠ OmniWM 側の `general.ipcEnabled = true` が前提
  #     （modules/apps/omniwm/settings.nix で宣言済み）。
  launchd.agents.desktop-auto = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.profileDirectory}/bin/omniwmctl"
        "watch"
        "display-changed"
        "--exec"
        "${config.home.homeDirectory}/bin/desktop-auto"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      # desktop-auto は omniwmctl / jq / desktop-switch を名前で呼ぶ。
      EnvironmentVariables.PATH = lib.concatStringsSep ":" [
        "${config.home.profileDirectory}/bin"
        "${config.home.homeDirectory}/bin"
        "/usr/bin"
        "/bin"
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/desktop-auto.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/desktop-auto.err.log";
    };
  };
}
