{pkgs, ...}: {
  ##########################################################################
  #
  #  bitwarden — fleet 横断の秘密ストア（D1 層）の CLI 側。
  #
  #  D1/D2 の秘密二層の定義は vault の fleet-home-directory-design が正本。
  #  GUI（Bitwarden.app）は modules/base/homebrew-base/darwin.nix の cask（理由もそこ）。
  #  アカウント作成〜結線の手順は vault の runbook-bitwarden-rbw が正本。
  #
  #  ## なぜ公式 `bw` ではなく `rbw` か
  #
  #  公式 `bw` はステートレスで、呼ぶたびに `BW_SESSION` を自分で管理する必要がある。
  #  `rbw` は `rbw-agent`（ssh-agent と同じ発想）が解錠状態をメモリに保持するので、
  #  スクリプトから `rbw get <name>` を叩くだけで値が取れる＝無人性が高い。
  #  非公式実装なのは承知の上（公式 `bw` は nixpkgs の `bitwarden-cli` でいつでも足せる）。
  #
  #  ## 設定ファイルを配らない理由（＝このモジュールに無いものの説明）
  #
  #  実体は macOS では `~/Library/Application Support/rbw/config.json`（XDG の
  #  ~/.config ではない。rbw が directories crate のプラットフォーム既定に従う。
  #  実測 2026-09-03）。これは `rbw config set` が**書き換える**ファイルなので、
  #  nix store への symlink にすると読み取り専用になって `rbw config set` /
  #  `rbw login` が失敗する。よって宣言せず、runbook 側の手順で設定する。
  #
  ##########################################################################

  home.packages = with pkgs; [
    rbw # 非公式 Bitwarden CLI（Rust）。rbw-agent が解錠状態を保持する
    pinentry_mac # rbw のマスターパスワード入力ダイアログ。無いと unlock できない
  ];
}
