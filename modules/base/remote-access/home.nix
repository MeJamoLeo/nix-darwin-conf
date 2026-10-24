# 機体どうしの ssh クライアント設定（mac・x1nano 共通）。
# ogasawara へは tailnet の 2222 番（素の sshd）に入る。22 番は Tailscale SSH が受けていて、
# リモートコマンドの終了コードを返さないため herdr --remote などが壊れる（経緯は hosts/ogasawara.nix）。
# 2222 は 22 とは別のホスト鍵（macOS の sshd の鍵）なので、初回だけ accept-new で覚えさせる。
{...}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings.ogasawara = {
      Port = 2222;
      StrictHostKeyChecking = "accept-new";
    };
  };
}
