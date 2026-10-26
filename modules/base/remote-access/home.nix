# 機体どうしの ssh クライアント設定（mac・x1nano 共通）。
# ogasawara へは tailnet の 22 番（Tailscale SSH）でそのまま入る。ホスト固有の指定は不要。
#
# ★ 2026-10-24 は「22 番は Tailscale SSH が終了コードを返さず herdr --remote が壊れる」ため
#   ogasawara に素の sshd を 2222 で立て、ここから向けていた。2026-10-25 に方針変更し、
#   自作の sshd を保守せず herdr を v0.9.3 に固定する形にした（理由は flake.nix の herdr input）。
#   Tailscale SSH の終了コードが壊れている事実は変わらないので、終了コードで分岐する
#   スクリプトを ogasawara 相手に書くときは注意する（`ssh ogasawara 'exit 7'` が 0 を返す）。
#
# 2026-10-25: fleet の機体に ~/.ssh/config のエイリアスを与えた。ssh 自体は MagicDNS で
# 今まで通り素通りするので、この追加は「ssh config から Host 一覧を拾う GUI」(Orca の
# Add remote host 等)に機体を見せるためのもの。HostName は書かない——名前解決は今まで
# 通り MagicDNS に任せ、known_hosts のエントリ(素のホスト名)もそのまま効かせる。
{...}: let
  fleetHost = {
    User = "treo";
    IdentityFile = "~/.ssh/id_ed25519";
    IdentitiesOnly = "yes";
    AddKeysToAgent = "yes";
  };
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      ogasawara = fleetHost;
      tanegashima = fleetHost;
      x1nano = fleetHost;
    };
  };
}
