{
  pkgs,
  lib,
  config,
  ...
}: {
  # enable flakes globally
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.package = pkgs.nix;

  # 週次 GC: 参照されなくなった store path を回収する後片付け役。
  # 世代数の上限は下の activationScript で管理するので、
  # age-based は long tail の保険として 14d に緩めておく。
  nix.gc = {
    automatic = lib.mkDefault true;
    interval = {
      Weekday = 0;
      Hour = 5;
      Minute = 0;
    }; # Every Sunday at 5:00 AM
    options = lib.mkDefault "--delete-older-than 14d";
  };

  # darwin-rebuild switch のたびに system profile を最新 10 世代に絞る。
  # nix.gc は age ベースしか受け付けないため、count 制限はこちらで担当。
  # flake.lock が git にある前提で、10 世代 ≒ 数日分の instant rollback を確保。
  system.activationScripts.pruneNixGenerations.text = ''
    echo "[nix] pruning system generations to latest 10"
    ${config.nix.package}/bin/nix-env \
      --profile /nix/var/nix/profiles/system \
      --delete-generations +10 || true
  '';

  # Disable auto-optimise-store because of this issue:
  #   https://github.com/NixOS/nix/issues/7273
  # "error: cannot link '/nix/store/.tmp-link-xxxxx-xxxxx' to '/nix/store/.links/xxxx': File exists"
  nix.settings = {
    auto-optimise-store = false;
  };
}
