# NixOS 機の土台（macos-defaults の NixOS 版）。ブート・ネットワーク・ロケール・コンソール。
{pkgs, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";
  console.useXkbConfig = true;

  environment.systemPackages = with pkgs; [vim wget curl];
}
