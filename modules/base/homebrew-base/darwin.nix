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
      # Firefox 系だが brew 版＝署名済み .app なので policies.json を置けず、拡張を宣言的に
      # 入れられない（Zen は macOS の Managed Preferences も読まない: zen-browser/desktop#12363）。
      # nix に固定する道はあるが日常ブラウザの自動更新が死ぬので採らない（2026-08-03 判断）。
      # 新端末では AMO から手で入れる:
      #   uBlock Origin / Vimium / Video Speed Controller / Unhook / Tampermonkey /
      #   Obsidian Web Clipper
      # ⚠ 広告ブロッカーは uBO に固定。AdGuard と併用するとフィルタが二重適用される。
      "zen"

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
      "dynalist" # Outliner and list making app
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
