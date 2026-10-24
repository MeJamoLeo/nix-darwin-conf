# リモートアクセス（NixOS 版）。darwin.nix と同じ方針：tailscale ＋ mosh ＋ 鍵だけの sshd。
# 公開鍵は repo 直下の keys.nix（デバイス台帳）から選ぶ。
{
  pkgs,
  username,
  ...
}: let
  keys = import ../../../keys.nix;
in {
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = ["tailscale0"];
  # MagicDNS で `ssh ogasawara` のように名前で届かせる（mac と同じ）。systemd-resolved が
  # あれば tailscale は tailnet の名前だけを引き受ける split DNS になり、それ以外の
  # 問い合わせは今まで通り NetworkManager が持ってきた DNS へ流れる。
  services.resolved.enable = true;
  services.tailscale.extraSetFlags = ["--accept-dns=true"];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false; # 鍵のみ（グローバル IPv6 に晒れるため）
      KbdInteractiveAuthentication = false;
    };
  };
  programs.mosh.enable = true;
  environment.systemPackages = [pkgs.ghostty.terminfo];

  users.users.${username}.openssh.authorizedKeys.keys = [
    keys.ogasawara
    keys.tanegashima
  ];
}
