# ホスト名とユーザー（NixOS 版）。ログインシェルは zsh（mac と揃える）。
{
  pkgs,
  username,
  hostname,
  ...
}: {
  networking.hostName = hostname;
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    home = "/home/${username}";
    shell = pkgs.zsh;
    extraGroups = ["wheel" "networkmanager" "video" "input"];
  };
  programs.zsh.enable = true;
}
