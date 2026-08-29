{...}:
# Zen（Firefox フォーク）— 既製品の設定値なので apps バケツ。
#
# ## なぜ homebrew cask から flake の home-manager モジュールへ移したか（2026-08-27）
#
# Zen の **Space / Folder / ピン留め**は prefs ではなく実行時ステートに入っている：
#   - Space・Folder・pin  → プロファイル内 `zen-sessions.jsonlz4`（LZ4 圧縮 JSON）
#   - Space のブックマーク → `places.sqlite` の `zen_bookmarks_workspaces` テーブル
# よって cask + `home.file` で user.js を置く旧構成では **prefs までしか宣言できない**。
# zen-browser-flake の HM モジュールは activation script で jsonlz4 を展開 → jq で
# upsert → 再圧縮するので、Space と Folder を宣言的に固定できる（flake.nix の input
# コメントも参照）。
#
# ## Mozilla アカウントの Sync では代替にならない（調査済み・2026-08-27）
#
# Zen は Firefox Sync に乗るので bookmarks / passwords / history / 拡張 / 開いてるタブは
# 同期するが、**Space は stable では同期しない**（Twilight で実装中。desktop#11407 /
# #12339 / #12749）。Folder とタブ配置はローカルステートで、公式の Window Sync も
# 「同一デバイスのウィンドウ間」限定。したがって固定するなら宣言的にやるしかない。
#
# ## 既存プロファイルの乗っ取り（重要）
#
# mkFirefoxModule は darwin で `profilesPath = <configPath>/Profiles` を使い、
# profiles.ini に `Path = Profiles/<profile.path>` を書く。`path` を**実在の
# プロファイルディレクトリ名**に合わせることで、10MB の places.sqlite・logins.db・
# 拡張7個が入った既存プロファイルをそのまま引き継ぐ（新規プロファイルを作らせない）。
#
# ⚠ この値は `~/Library/Application Support/zen/profiles.ini` の `[Install…] Default`
#   と一致していなければならない。Zen 側でプロファイルを作り直したらここを更新する。
#   ※ configPath は上流モジュールが大文字の `…/Zen` を使うが、macOS の APFS は
#     既定で case-insensitive なので実体の `…/zen` と同じディレクトリに解決する（実測確認済み）。
#
# ⚠ profiles.ini は nix 管理のシンボリックリンクになる。既存ファイルは
#   home-manager の backupFileExtension により `.hm-backup` に退避される。
#   `installs.ini` は非管理のまま残る（Zen が書く可変ファイル）。
#
# ### ⚠⚠ dedicated profile ＝ 移行時に一度だけ手当てが要る（2026-08-27 に踏んだ）
#
# Firefox 67+ は **.app のパスから計算したインストールハッシュごとに専用プロファイルを持つ**。
# `installs.ini` に自分のハッシュが無いと、**profiles.ini の `Default=1` にフォールバックせず
# 意図的に新規プロファイルを作る**（作られた profile の times.json が
# `"source": "firstrun-skipped-default"` と言う）。cask 版と nix 版は .app パスが違う＝
# 別インストール扱いなので、移行直後の初回起動でこれが起きる。
# しかも新規プロファイルを profiles.ini に登録しようとして、**profiles.ini が /nix/store への
# 読み取り専用リンク**なので書けず、`Profile Missing` ダイアログで停止する。
#
# 対処は `installs.ini` の当該ハッシュ行を既存プロファイルに向けるだけ（1回きり）：
#
#   [DFEDCF58DA149FC0]                              ← nix 版 Zen のインストールハッシュ
#   Default=Profiles/tof5kg3s.Default (release)-1   ← ここを既存プロファイルにする
#
# このハッシュが**バージョン更新で変わらない**のは flake 側の設計による。package.nix:82 が
# `$HOME/Applications/Home Manager Apps/<app>.app` という安定パス経由で起動するラッパーを
# 作っている（"Use symlink path to avoid installs.ini accumulation on Nix rebuilds"）。
# Dock の固定先も同じ安定パスなので揃っている。→ 手当ては移行時の1回だけで済む。
#
# ## Space / pin を宣言しはじめたときの運用上の注意
#
#   - `darwin-rebuild switch` の前に **Zen を終了**させること（activation script が
#     zen-sessions.jsonlz4 に排他アクセスを要る）。何も宣言していない間は session writer
#     自体が走らないので、この制約は掛からない（store.nix の profilesWithSessionData 参照）。
#   - Space は `uuid` 一致でマージされるので、既存 Space の id を書けば重複しない。
#     pin は `zenSyncId` 一致で照合するが、Zen が自動生成する既存 id はタイムスタンプ形式
#     （例 `1783379884207-81`）で UUID と噛み合わない。**既存の pin を宣言に載せ替えるには
#     `pinsForce = true` が要る**（さもないと同じ URL の pin が二重に生える）。
#
# ## .app の置き場所が変わる
#
# `darwin.packageMode = "signed"`（既定）は upstream の .app を無改変で入れるので
# Team ID 依存の統合（1Password・iCloud Passwords・Touch ID・Gatekeeper）が壊れない。
# 代償として wrapFirefox 系の機能（extraPrefs / extraPrefsFiles / pkcs11Modules）は使えない。
# 実体は `~/Applications/Home Manager Apps/Zen Browser (Beta).app`（Zed・AeroSpace と
# 同じ扱い）になり、`/Applications/Zen.app` は生えない。**バンドル名が cask 版と違う**
# 点に注意（upstream の .app を無改変で入れるので改名されない）。バンドル ID は同じ
# `app.zen-browser.zen`、署名の TeamIdentifier も `9V5K9TP787` のままであることを実測確認済み。
# Dock の固定先は macos-defaults/darwin.nix で追従させてある。
#
# ⚠ 同じバンドル ID の .app が2つ（旧 cask の /Applications/Zen.app と nix 版）あると
#   LaunchServices の既定ブラウザ解決が不定になる。移行を確認したら
#   `brew uninstall --cask zen` で旧実体を消すこと。
{
  programs.zen-browser = {
    enable = true;

    # 既定値だが、署名を保つ選択は Team ID 統合の前提なので明示しておく。
    darwin.packageMode = "signed";

    # policies は `targets.darwin.defaults` 経由で `app.zen-browser.zen` ドメインに
    # 書かれる（.app の中には触らない）。ただし Zen が enterprise policy を defaults
    # ドメインから読むかは **未検証**（desktop#12363 は Managed Preferences を読まない
    # という別件）。効くと分かるまで空にしておき、遮断は user.js 経路（youtube-gate）に
    # 一本化する。
    policies = {};

    profiles.default = {
      id = 0;
      name = "Default (release)-1";
      path = "tof5kg3s.Default (release)-1";
      isDefault = true;

      # user.js の中身は関心事ごとに各モジュールが寄せる（nix の attrset マージ）：
      #   - modules/custom/youtube-gate/home.nix … PAC による YouTube 遮断
      # ここには Zen 固有の一般設定だけを置く。
      settings = {
        # 既定ブラウザ確認のダイアログを出さない（既定は macOS 側で管理する）。
        "browser.shell.checkDefaultBrowser" = false;
      };
    };
  };
}
