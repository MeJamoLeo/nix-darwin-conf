{pkgs, ...}: {
  ##########################################################################
  #
  #  discord — Discord bot token を Bitwarden(D1) から供給して REST API を叩く層。
  #
  #  価値の中心が自作スクリプトなので custom バケツ（modules/CLAUDE.md の決定手順 2）。
  #  Discord.app 本体は既製品なので modules/base/homebrew-base/darwin.nix の cask。
  #
  #    discord-api   rbw get → curl。token を argv/stdout に載せずに API を叩く。
  #                  GET 以外は --write 必須、DELETE は --allow-delete も必須。
  #    discord-apply spec JSON を正本にカテゴリ/チャンネルを収束させる（削除機能なし）。
  #                  state を持たず毎回 Discord を読む＝別の正史を作らない。
  #
  #  spec JSON は**この repo に置かない**（2026-09-04 の判断）。Discord 自身が
  #  チャンネル構成の正史で、spec はそこから導出できる＝保存すると二重化して drift する。
  #  spec は apply 一回きりの入力として手元に書いて捨てる。将来 spec を戻したくなったら
  #  discord-apply に --export（現構成を spec 形式で吐く）を足すほうが筋が良い。
  #
  #  依存（いずれも PATH 解決。宣言元を書いておく）:
  #    rbw   modules/apps/bitwarden/home.nix
  #    jq    modules/apps/core-packages/home.nix
  #    curl  modules/base/homebrew-base/darwin.nix（brews。nixpkgs 版は macOS で不調）
  #
  #  bot の作成・招待・権限の手順は vault の runbook-discord-bot-access が正本。
  #
  ##########################################################################

  home.packages = [
    (pkgs.writeShellScriptBin "discord-api" (builtins.readFile ./scripts/discord-api))
    # python は writers.writePython3Bin ではなく素の exec で包む（flake8 チェックを
    # 通すためだけに書式を歪めない。cp/tools が python3 を呼ぶのと同じ流儀）。
    (pkgs.writeShellScriptBin "discord-apply" ''
      exec ${pkgs.python3}/bin/python3 ${./scripts/discord-apply.py} "$@"
    '')
  ];
}
