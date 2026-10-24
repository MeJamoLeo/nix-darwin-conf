{
  pkgs,
  username,
  nixvim,
  zen-browser,
  ...
}: {
  ##########################################################################
  #
  #  nixos-laptop — 「私の NixOS ノート」という役割のセットメニュー（x1nano）。
  #
  #  mac-workstation.nix と対になる。共通のソフト（shell / git / tmux / nixvim /
  #  starship / herdr / claude / zen 等）は **mac と同じ modules/apps/*/home.nix**
  #  を読む＝設定は1か所。OS で違う部分はモジュールの中で分岐させる。
  #  ここに並ぶ nixos.nix と Linux 専用の home.nix だけが NixOS 側の差分。
  #
  ##########################################################################

  # ── システム層（NixOS）──────────────────────────────────
  imports = [
    ../modules/base/nix-core/nixos.nix
    ../modules/base/nixos-defaults/nixos.nix
    ../modules/base/host-users/nixos.nix
    ../modules/base/remote-access/nixos.nix
    ../modules/base/laptop/nixos.nix
    ../modules/apps/niri/nixos.nix # デスクトップ＋greetd(tuigreet→zsh)
    ../modules/apps/fcitx5/nixos.nix
    ../modules/apps/claude/nixos.nix # managed settings（mac の darwin.nix と同じ JSON）
    ../modules/custom/cp/print/nixos.nix
    ../modules/domain/school/cs4371/nixos.nix
  ];

  # ── ユーザー層（home-manager）───────────────────────────
  home-manager.users.${username} = {
    imports = [
      # base
      ../modules/base/forge/home.nix
      # apps — mac と共通
      ../modules/apps/shell/home.nix
      ../modules/apps/core-packages/home.nix
      ../modules/apps/git/home.nix
      ../modules/apps/tmux/home.nix
      ../modules/apps/nixvim/home.nix
      ../modules/apps/starship/home.nix
      ../modules/apps/herdr/home.nix
      ../modules/apps/claude/home.nix
      ../modules/apps/bitwarden/home.nix
      ../modules/apps/zen/home.nix
      ../modules/apps/sioyek/home.nix
      # apps — Linux だけ
      ../modules/apps/niri/home.nix
      ../modules/apps/dms/home.nix
      ../modules/apps/kitty/home.nix
      ../modules/apps/wayvibes/home.nix
      # custom
      ../modules/custom/cp/tools/home.nix
      # 外部 flake 供給の HM モジュール
      ((nixvim.homeModules or nixvim.homeManagerModules).nixvim)
      zen-browser.homeModules.default
    ];

    home = {
      username = username;
      homeDirectory = "/home/${username}";
      stateVersion = "24.11"; # 旧 nixos-cp のまま（HM の互換値。上げる必要は無い）
    };
    programs.home-manager.enable = true;

    # mac は OS 付属の python3（Xcode CLT）を使っているので core-packages に無い。
    # NixOS には無いので足す（cp-test・AtCoder の Python 提出の実行に要る）。
    home.packages = with pkgs; [python3 htop];
  };
}
