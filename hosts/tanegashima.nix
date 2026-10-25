# tanegashima — MacBook Air M1（持ち出し機）。
# 役割は mac-workstation そのもので、機体固有の差分は todo のリモートラッパーだけ。
{username, ...}: {
  imports = [
    ../profiles/mac-workstation.nix

    # Orca（エージェント並列実行の ADE・homebrew cask）。dejima には配らないので
    # profile ではなく mac 2台から個別に import する。
    ../modules/apps/orca/darwin.nix
  ];

  # todo-board の本体（home.nix）は ogasawara 専用（データの正本 ~/Store が母艦にあるため）。
  # tanegashima には `todo` を「母艦へ SSH して実行する薄いラッパー」として入れる。
  home-manager.users.${username}.imports = [
    ../modules/custom/todo-board/remote.nix

    # REA（逆アセンブラを持つ MCP サーバ）。本体は npm global 運用なので、
    # ここが宣言するのは Ghidra / JDK / npm prefix だけ。詳細はモジュール冒頭。
    ../modules/apps/rea/home.nix
  ];
}
