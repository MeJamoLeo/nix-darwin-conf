{
  pkgs,
  lib,
  ...
}: {
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
  #  ## 設定ファイルの扱い（symlink にはしない・でも宣言はする）
  #
  #  実体は macOS では `~/Library/Application Support/rbw/config.json`（XDG の
  #  ~/.config ではない。rbw が directories crate のプラットフォーム既定に従う。
  #  実測 2026-09-03）。これは `rbw config set` / `rbw login` が**書き換える**
  #  ファイルなので、nix store への symlink にすると読み取り専用になって失敗する。
  #
  #  → だが「宣言しない」では伝播しない（2026-09-22 の教訓）。
  #  アプリが実行時に所有するファイルは **store symlink で奪わず activation で
  #  実ファイルを書く**（2026-08-30 の omniwm 移行で確立した手）。ここでは
  #  **`pinentry` の1キーだけ** jq で当て、rbw 自身が書くキー（email・ログイン
  #  状態）には触らない。下の rbwPinentry を参照。
  #
  #  ## pinentry は curses 一本（GUI は使わない・2026-10-02）
  #
  #  rbw は pinentry を**1つしか**指定できない（config の `pinentry` キー）。
  #  以前は `pinentry_mac`（GUI ダイアログ）だったが、**ssh 越しのセッションには
  #  ダイアログを出す画面が無く、遠隔で unlock できない**ので curses に替えた。
  #  母艦（ogasawara）を AI の実行ホストにし、他機体からは ssh で入る構成にしたため
  #  （vault の 2026-10-02-ai-host-consolidation が正本）。
  #
  #  GUI 版は**併置しない**。rbw を呼ぶのは端末から起動される経路だけで、
  #  tty を持たない呼び出し元（launchd 配下の常駐ジョブ等）が無いため
  #  （常駐チャットブリッジの構想はセキュリティ上の理由で撤回済み）。
  #  必要になったら実行時に分岐するラッパーを足す。
  #
  #  承知の上のトレードオフ: **TUI のプロンプトは同じ端末の任意のプロセスから
  #  偽装できる**。GUI ダイアログは macOS 自身が描くのでその点は強かった。
  #  マスターパスワードは D1 層の鍵なので、打つ回数は最小に保つ
  #  （rbw-agent が解錠状態を保持する ＝ lock_timeout 内は再入力不要）。
  #
  #  注意: pinentry-curses は homebrew にも居るが（gnupg / gpgme / poppler の
  #  推移的依存で、`brew leaves` に出ない）、宣言していないものは伝播しないので
  #  参照しない。nixpkgs の pinentry-curses は aarch64-darwin 対応（実測 2026-10-02）。
  #
  ##########################################################################

  #  ## 消費側の共通入口（2026-10-13・rbw の統一）
  #
  #    secret-get    rbw get の唯一の入口。施錠中は解錠を試みず案内して exit 4
  #                  （tty の無い呼び出し元が pinentry 待ちで固まるのを防ぐ）。
  #                  手動ツールはすべてこれ経由で読み、Keychain は読まない。
  #    secret-cache  Bitwarden → login Keychain の派生キャッシュを作る。
  #                  launchd ジョブ（todo-board・cp dashboard）用。
  #
  #  消費スクリプトは rbw を直に叩かない。Claude が secret-get を直接叩くのは
  #  modules/apps/claude/deny-secret-reads.sh で deny。

  home.packages = with pkgs; [
    rbw # 非公式 Bitwarden CLI（Rust）。rbw-agent が解錠状態を保持する
    pinentry-curses # マスターパスワードの入力。無いと unlock できない
    (writeShellScriptBin "secret-get" (builtins.readFile ./scripts/secret-get))
    (writeShellScriptBin "secret-cache" (builtins.readFile ./scripts/secret-cache))
  ];

  # rbw の config.json に pinentry の選択だけを宣言的に当てる。
  # 全体を上書きしない理由は上のコメント（email・ログイン状態は rbw の持ち物）。
  # 冪等: 既に目的の値なら何もしない。ファイルが無ければ最小構成で作る
  # （新しい機体で `rbw login` 前に activation が走っても壊れないように）。
  #
  # lock_timeout も同じ手で当てる（2026-10-23・3600 → 28800 = 8時間）。
  # 理由: 毎回の unlock 入力が負担で使われなくなる方が害が大きい。
  # トレードオフ: 解錠中は同一ユーザーの全プロセス（Claude を含む）が秘密を
  # 取り出せるので、prompt injection を受けたときに被害が起き得る時間が延びる。
  # 緩和策の候補（未着手）: スリープ・画面ロック時に `rbw lock`。
  home.activation.rbwPinentry = lib.hm.dag.entryAfter ["writeBoundary"] ''
    cfg="${
      if pkgs.stdenv.hostPlatform.isDarwin
      then "$HOME/Library/Application Support/rbw/config.json"
      else "\${XDG_CONFIG_HOME:-$HOME/.config}/rbw/config.json"
    }"
    want="pinentry-curses"
    wantLock=28800
    mkdir -p "$(dirname "$cfg")"
    if [ ! -e "$cfg" ]; then
      printf '{"pinentry":"%s","lock_timeout":%s}\n' "$want" "$wantLock" > "$cfg"
    elif [ "$(${pkgs.jq}/bin/jq -r '.pinentry // ""' "$cfg")" != "$want" ] \
      || [ "$(${pkgs.jq}/bin/jq -r '.lock_timeout // ""' "$cfg")" != "$wantLock" ]; then
      tmp="$(mktemp)"
      ${pkgs.jq}/bin/jq --arg v "$want" --argjson l "$wantLock" \
        '.pinentry = $v | .lock_timeout = $l' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    fi
  '';
}
