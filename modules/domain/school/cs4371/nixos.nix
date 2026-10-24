# CS4371（セキュリティ）の実験環境。VirtualBox で攻撃/標的 VM を回し、Wireshark で観測する。
# 学期が終わったら modules/_archive/ へ（domain/school の他の科目と同じ扱い）。
{
  config,
  pkgs,
  username,
  ...
}: let
  # ⚠ 一時回避（2026-10-23）：nixos-unstable の aggregateModules が外部モジュールごとの
  #   証明書 <module>.ko.cer を cat で連結するようになった（nixpkgs 6bd7526744, 10-13）が、
  #   VirtualBox のモジュールは .cer を出さないので `cat: misc/vboxdrv.ko.cer: No such file`
  #   でシステムのビルドが落ちる。上流の issue: https://github.com/NixOS/nixpkgs/issues/575192
  #   （修正は各パッケージ側で進行中）。空の .cer を置いて cat を通すだけ＝署名には影響しない。
  #   virtualbox の修正が入ったらこの let と extraModulePackages の行を消す。
  kernel = config.boot.kernelPackages.kernel;
  vboxCerStub = pkgs.runCommand "vbox-ko-cer-stub-${kernel.modDirVersion}" {} ''
    d=$out/lib/modules/${kernel.modDirVersion}/misc
    mkdir -p $d
    for m in vboxdrv vboxnetflt vboxnetadp; do : > $d/$m.ko.cer; done
  '';
in {
  virtualisation.virtualbox.host.enable = true;
  boot.extraModulePackages = [vboxCerStub];

  programs.wireshark.enable = true;
  users.users.${username}.extraGroups = ["vboxusers" "wireshark"];
}
