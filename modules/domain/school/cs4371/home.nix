# CS4371 のラボ用ゲスト VM（VirtualBox の host-only ネットワーク）への ssh。
# 専用鍵 ~/.ssh/id_cs4371 を使い、メインの id_ed25519 から切り離す。
# もとは x1nano の手書き ~/.ssh/config にあったもの（programs.ssh を宣言化したので移した）。
{...}: {
  programs.ssh.settings."192.168.56.101 192.168.56.102" = {
    User = "spurs";
    IdentityFile = "~/.ssh/id_cs4371";
    IdentitiesOnly = "yes";
    StrictHostKeyChecking = "accept-new";
  };
}
