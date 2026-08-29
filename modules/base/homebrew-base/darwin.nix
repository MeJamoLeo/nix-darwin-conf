{
  pkgs,
  username,
  ...
}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false; # Don't auto-fetch Homebrew updates on rebuild (run `brew update` manually)
      upgrade = false; # Don't auto-upgrade casks/formulae/mas apps on rebuild (run `brew upgrade` / `mas upgrade` manually)
      # Don't auto-uninstall on rebuild — the interactive [y/n] prompt blocks non-interactive runs,
      # and it would also try to remove pre-existing App Store apps (GarageBand, Keynote, etc.).
      # Run `brew bundle cleanup --force` manually when desired.
      cleanup = "none";
    };

    # Applications to install from Mac App Store using mas.
    # You need to install all these Apps manually first so that your apple account have records for them.
    # otherwise Apple Store will refuse to install them.
    # For details, see https://github.com/mas-cli/mas
    masApps = {
      DisplayMenu = 549083868; # Menu bar tool for display management
      Keeby = 6760791739; # Mechanical keyboard sound effects
      LINE = 539883307; # Messaging app
      Xcode = 497799835; # Apple's IDE for macOS/iOS development
    };

    # nikitabobko/tap (aerospace) と FelixKratz/formulae (borders) は
    # nixpkgs 移行 (modules/apps/aerospace/home.nix) で不要に → 各機で手動
    # `brew untap nikitabobko/tap felixkratz/formulae`
    taps = [
      "homebrew/services"
    ];

    # `brew install` - Command line tools
    # direnv/wget/gh/lazygit は nixpkgs 管理へ移行 (modules/core-packages/home.nix 2026-07-08):
    # dejima は homebrew 無効なので brew だと headless 機に届かないため。
    # cleanup="none" で旧 formula は残る → 各機で手動
    # `brew uninstall direnv wget gh lazygit borders`
    brews = [
      "curl" # HTTP client (don't install via nixpkgs, not working well on macOS!)
      "mas" # Mac App Store CLI (required for `masApps` to work)
      # "neovim"  # Terminal-based text editor (nixvim manages nvim)
    ];

    # `brew install --cask` - GUI applications
    casks = [
      # Browsers
      "google-chrome" # Web browser
      "brave-browser" # Privacy-focused web browser
      # "zen" — 2026-08-27 に cask をやめ、flake の home-manager モジュールへ移した
      #   （modules/apps/zen/home.nix・flake.nix の zen-browser input）。
      #   2026-08-03 に cask を選んだ理由は「nix に固定すると日常ブラウザの自動更新が死ぬ」
      #   だったが、**Space / Folder が宣言できない**という代償のほうが重かったため反転。
      #   更新は `nix flake update zen-browser` で回す。
      #   ⚠ 実体は `~/Applications/Home Manager Apps/Zen Browser (Beta).app` に移る
      #     （/Applications には生えず、バンドル名も cask 版と違う）。旧 cask の
      #     /Applications/Zen.app は cleanup="none" のため残り、**同じバンドル ID の .app が
      #     2つあると既定ブラウザの解決が不定になる**ので、移行を確認したら一度だけ手で
      #     `brew uninstall --cask zen` すること。
      #   拡張は引き続き AMO から手で入れる（署名を保つ "signed" モードでは
      #   policies.json を .app に置けない）:
      #     uBlock Origin / Vimium / Video Speed Controller / Unhook / Tampermonkey /
      #     Obsidian Web Clipper
      #   ⚠ 広告ブロッカーは uBO に固定。AdGuard と併用するとフィルタが二重適用される。

      # Development
      "visual-studio-code" # Code editor
      "cursor" # AI-first code editor
      # zed は nixpkgs の zed-editor で管理 (modules/core-packages/home.nix)
      "claude" # Anthropic's AI assistant (GUI デスクトップ版。nixpkgs 非収録のため cask)
      # claude-code (CLI) は nixpkgs 管理へ移行 (modules/claude/home.nix)。cask だと
      # brew upgrade のたびに quarantine 付きで再DLされ、SSH 先で Gatekeeper の
      # 「DLされたアプリ」確認が出て詰まるため。cleanup="none" なので旧 cask は
      # 自動削除されない → 各機で手動 `brew uninstall --cask claude-code`
      "grok-build" # xAI Grok CLI (https://x.ai/cli) — installs `grok` and `agent`

      # Communication & Meetings
      "discord" # Chat and voice communication platform
      "zoom" # Video conferencing

      # Media / documents
      "obs" # Open Broadcaster Software for recording/streaming
      "spotify" # Music streaming service
      "iina" # Local media player (default open-with for audio; modules/apps/file-defaults)
      "notunes" # Block Apple Music auto-launch (media keys / BT); modules/apps/file-defaults
      "skim" # Default PDF viewer + LaTeX SyncTeX (was domain/latex; elevated for user-wide defaults)

      # Productivity & Organization
      "libreoffice" # Free office suite
      "obsidian" # Knowledge base that works on top of markdown files
      # "dynalist" — 2026-08-19 に外した。**cask が Homebrew から消滅**している
      #   （Casks/d/dynalist.rb も formulae.brew.sh の JSON API も 404）。ローカルには
      #   url も sha256 も空のスタブだけが残り、`brew bundle` の fetch 段が
      #   `attempted to use a `Downloadable` without a URL!` で落ちて **darwin-rebuild
      #   全体が失敗する**。宣言を残す限り毎回止まるので削除が唯一の解。
      #   /Applications/Dynalist.app は cleanup="none" のおかげで残っており、
      #   modules/base/macos-defaults/darwin.nix の Dock 常駐もそのまま効く。
      #   ただし **今後 brew 経由の更新は来ない**（1.0.6 で凍結）。
      #   完全に手を切るなら手動で `brew uninstall --cask dynalist`＋Dock の行も削除。
      "anki" # Spaced repetition flashcard program

      # Utilities
      "ghostty" # GUI terminal (nixpkgs は darwin 非対応→cask。設定は modules/ghostty/home.nix)
      # "cmux" # 引退（Ghostty + herdr へ移行）。tanegashima では 2026-07-30 に
      #        `brew uninstall --cask cmux` 済み。他機に残っていたら同様に手動削除。
      #        戻すならこの行を復活
      # 2026-07-30 棚卸し：nix 未宣言のまま brew に居残っていた gitkraken / slack /
      # visualvm を削除した（起動履歴：gitkraken 2026-04-21 が最後、slack と visualvm は
      # 一度も起動なし）。意図的に採用しなかったので宣言は足さない。
      # aerospace は nixpkgs 管理へ移行 (modules/apps/aerospace/home.nix 2026-07-08)。
      # 旧 cask は手動 `brew uninstall --cask aerospace`（quit してから）
      "raycast" # Productivity tool (HotKey: alt/option + space)
      # "stats" # 引退 2026-07-30。app は手動で Trash 済みなのに cask 宣言だけ残っていた
      #         ドリフト状態（login item も Trash 内の app を指したまま有効だった）。
      #         棚卸しで cask ごと削除。戻すならこの行を復活 + `brew install --cask stats`
      # "gyazo" # 引退 2026-07-30。ほとんど使っていないため。Gyazo.app / Gyazo Menu.app /
      #         Gyazo Video.app の3本立てで、Gyazo Menu が login item helper
      #         (com.gyazo.menu.helper) を有効化していた。戻すならこの行を復活 +
      #         `brew install --cask gyazo`
      "whatsapp" # WhatsApp desktop client
      # "caffeine" # 引退 2026-07-30。login item 整理で自動起動を切ったので宣言も外す。
      #            戻すならこの行を復活 + `brew install --cask caffeine`
      # VPN service。アプリ本体は使うので宣言は残す。2026-07-30 に自動起動だけ停止した：
      # `launchctl disable gui/501/com.surfshark.vpnclient.macos.direct.launchAgent`
      # これは launchd の override DB を書くので発火は止まるが、BTM の disposition は
      # enabled のまま＝System Settings のトグルは ON に見える（表示と実態が2層に分かれる）。
      # 単一ソースに揃えるなら Surfshark アプリ内の "Launch on startup" を OFF にする。
      # 戻すのは `launchctl enable gui/501/<同ラベル>`。
      "surfshark"
      "handy" # Speech to text application
    ];
  };
}
