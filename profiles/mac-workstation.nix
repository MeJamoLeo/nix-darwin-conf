{
  username,
  nixvim,
  neru,
  ...
}: {
  ##########################################################################
  #
  #  mac-workstation — 「私の作業用 mac」という役割のセットメニュー。
  #
  #  ogasawara / tanegashima がそのまま共有し、dejima は hosts/dejima.nix で
  #  引き算する。機体固有の差分はここに書かず hosts/<name>.nix へ。
  #
  #  モジュールの実体は modules/<topic>/ に居る（1 関心事 = 1 ディレクトリ、
  #  darwin.nix = システム層 / home.nix = ユーザー層）。
  #
  ##########################################################################

  # ── システム層（nix-darwin）─────────────────────────────
  imports = [
    ../modules/nix-core/darwin.nix
    ../modules/macos-defaults/darwin.nix
    ../modules/homebrew-base/darwin.nix
    ../modules/host-users/darwin.nix
    ../modules/remote-access/darwin.nix
    ../modules/network-block/darwin.nix
    ../modules/latex/darwin.nix
    ../modules/school/txst/darwin.nix
  ];

  # ── ユーザー層（home-manager）───────────────────────────
  home-manager.users.${username} = {
    imports = [
      # クロスプラットフォーム（home.nix のみ＝将来 Linux ホストにも入れられる候補）
      ../modules/shell/home.nix
      ../modules/core-packages/home.nix
      ../modules/git/home.nix
      ../modules/tmux/home.nix # ◆ homeModules.tmux として外部公開中
      ../modules/nixvim/home.nix
      ../modules/starship/home.nix
      ../modules/ghostty/home.nix
      ../modules/zed/home.nix
      ../modules/herdr/home.nix
      ../modules/claude/home.nix
      # mac 専用ツール
      ../modules/aerospace/home.nix
      ../modules/chrome-anjin/home.nix
      ../modules/handy/home.nix
      ../modules/neru/home.nix
      # ドメイン
      ../modules/latex/home.nix
      ../modules/cp/tools/home.nix
      ../modules/cp/dashboard/home.nix
      ../modules/school/txst/home.nix
      # 外部 flake 供給の HM モジュール
      ((nixvim.homeModules or nixvim.homeManagerModules).nixvim)
      neru.homeManagerModules.default
    ];

    home = {
      username = username;
      homeDirectory = "/Users/${username}";

      # Home Manager release compatibility。HM 本体の更新でこの値を変える必要はない。
      stateVersion = "24.05";
    };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    # スクショ保存先 (macos-defaults/darwin.nix screencapture.location) の存在保証。
    # ディレクトリが無いと macOS はスクリーンショットを黙って失敗させる。
    home.file."Downloads/screenshots/.keep".text = "";
  };
}
