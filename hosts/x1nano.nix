# x1nano — ThinkPad X1 Nano（NixOS）。2026-10-23 に旧 nixos-cp からこの flake へ移した。
{...}: {
  imports = [
    ../profiles/nixos-laptop.nix
    ./x1nano-hardware.nix
  ];

  # 最初に入れた NixOS の版。ステートフルなデータの互換のための値なので変えない。
  system.stateVersion = "24.11";
}
