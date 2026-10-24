# nix 本体の設定（NixOS 版）。darwin.nix と同じ方針：flakes 有効・unfree 許可。
# GC は home 側の programs.nh.clean（modules/apps/core-packages）に任せる。
{username, ...}: {
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = [username];
    auto-optimise-store = false;
  };
  nixpkgs.config.allowUnfree = true;
}
