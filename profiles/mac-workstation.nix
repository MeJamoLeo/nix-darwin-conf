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
  #  モジュールの実体は modules/<kind>/<topic>/ に居る（<kind> = base/apps/custom/
  #  domain の種別バケツ。1 関心事 = 1 ディレクトリ、darwin.nix = システム層 /
  #  home.nix = ユーザー層）。置き場所ルールは modules/CLAUDE.md。
  #
  ##########################################################################

  # ── システム層（nix-darwin）─────────────────────────────
  imports = [
    ../modules/base/nix-core/darwin.nix
    ../modules/base/macos-defaults/darwin.nix
    ../modules/base/homebrew-base/darwin.nix
    ../modules/base/host-users/darwin.nix
    ../modules/base/remote-access/darwin.nix
    ../modules/custom/network-block/darwin.nix
    ../modules/domain/latex/darwin.nix
    ../modules/domain/school/txst/darwin.nix
  ];

  # ── ユーザー層（home-manager）───────────────────────────
  home-manager.users.${username} = {
    imports = [
      # apps — 既製品 + 設定値
      ../modules/apps/shell/home.nix
      ../modules/apps/core-packages/home.nix
      ../modules/apps/git/home.nix
      ../modules/apps/tmux/home.nix # ◆ homeModules.tmux として外部公開中
      ../modules/apps/nixvim/home.nix
      ../modules/apps/starship/home.nix
      ../modules/apps/ghostty/home.nix
      ../modules/apps/zed/home.nix
      ../modules/apps/herdr/home.nix
      ../modules/apps/claude/home.nix
      ../modules/apps/aerospace/home.nix
      ../modules/apps/handy/home.nix
      ../modules/apps/neru/home.nix
      # custom — 自作システム
      ../modules/custom/chrome-anjin/home.nix
      ../modules/custom/cp/tools/home.nix
      ../modules/custom/cp/dashboard/home.nix
      # domain — 生活ドメイン
      ../modules/domain/latex/home.nix
      ../modules/domain/school/txst/home.nix
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
