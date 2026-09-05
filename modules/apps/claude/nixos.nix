{pkgs, ...}: {
  ##########################################################################
  #
  #  claude (NixOS システム層) — Claude Code の managed settings（Linux 側）。
  #
  #  darwin.nix と対になるモジュール。JSON は managed-settings.nix（単一源）。
  #  Linux の managed settings パスは /etc/claude-code/managed-settings.json
  #  （公式ドキュメント確認済み 2026-09-05）。environment.etc は root 所有で
  #  置くので、macOS 側と同じく user 権限では外せない。
  #
  #  取り込み方（homeModules.tmux / forge と同じ共有パターン）：
  #    NixOS 側 flake で inputs.nix-darwin-conf.nixosModules.claude-managed-settings
  #    を imports に足す。
  #
  ##########################################################################
  environment.etc."claude-code/managed-settings.json" = {
    source = import ./managed-settings.nix {inherit pkgs;};
    mode = "0444";
  };
}
