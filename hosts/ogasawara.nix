# ogasawara — Mac mini M4（母艦）。
# 役割は mac-workstation そのもので、機体固有の差分は Hermes Agent だけ。
{username, ...}: {
  imports = [
    ../profiles/mac-workstation.nix

    # Orca（エージェント並列実行の ADE・homebrew cask）。dejima には配らないので
    # profile ではなく mac 2台から個別に import する。
    ../modules/apps/orca/darwin.nix
  ];

  # ★ tailnet 越しの ssh は 22 番（Tailscale SSH）のまま。2026-10-24 に「Tailscale SSH が
  #   リモートコマンドの終了コードを返さず herdr --remote が落ちる」対策として素の sshd を
  #   2222 で立てたが、2026-10-25 に撤回した（自作 daemon を保守しない方針）。
  #   代わりに herdr を v0.9.3 に固定している。経緯と解除条件は flake.nix の herdr input。

  # Hermes Agent はこの機体限定。**profile（＝全機共有）に入れない**理由：
  #   - hermes-agent#default は公開バイナリキャッシュが無く、実測で 1191 derivation の
  #     ローカルビルド＋1.5GiB DL / 6.3GiB 展開（uv2nix が Python ホイールを大量に
  #     ソースビルドする）。tanegashima（M1 Air）と dejima（使い捨て VM）に同じ負荷を
  #     掛ける意味が無い。
  #   - Hermes は cron / gateway で常駐して初めて価値が出るので、常時起動の母艦に
  #     1台だけ置くのが用途とも噛み合う。
  # 他機に広げたくなったら、このブロックを profiles/mac-workstation.nix へ移す。
  home-manager.users.${username}.imports = [
    ../modules/apps/hermes/home.nix
    ../modules/custom/todo-board/home.nix
    ../modules/custom/mail-check/home.nix
    # ../modules/custom/job-watch/home.nix # 一時停止(2026-10-18): job-watch/ が未追跡で評価が落ちるため。仕上げたら戻す

    # REA（逆アセンブラを持つ MCP サーバ）。本体は npm global 運用なので、
    # ここが宣言するのは Ghidra / JDK / npm prefix だけ。詳細はモジュール冒頭。
    ../modules/apps/rea/home.nix
  ];
}
