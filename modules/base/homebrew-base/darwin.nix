{
  pkgs,
  username,
  ...
}: {
  ##########################################################################
  #
  #  Install all apps and packages here.
  #
  # TODO Fell free to modify this file to fit your needs.
  #
  ##########################################################################

  # Install packages from nix's official package repository.
  #
  # The packages installed here are available to all users, and are reproducible across machines, and are rollbackable.
  # But on macOS, it's less stable than homebrew.
  #
  # Related Discussion: https://discourse.nixos.org/t/darwin-again/29331
  # CLI ツールは modules/core-packages/home.nix で home.packages 管理。
  # EDITOR は modules/shell/home.nix で home.sessionVariables 管理。
  # システム全体に必要なものだけ environment.systemPackages に置く。

  # TODO To make this work, homebrew need to be installed manually, see https://brew.sh
  #
  # The apps installed by homebrew are not managed by nix, and not reproducible!
  # But on macOS, homebrew has a much larger selection of apps than nixpkgs, especially for GUI apps!
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
      # TODO Feel free to add your favorite apps here.
      DisplayMenu = 549083868; # Menu bar tool for display management
      Klack = 6446206067; # Mechanical keyboard sound effects
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
      "zen" # Firefox-based privacy browser (install Vimium-FF manually from addons.mozilla.org)

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

      # Media
      "obs" # Open Broadcaster Software for recording/streaming
      "spotify" # Music streaming service

      # Productivity & Organization
      "libreoffice" # Free office suite
      "obsidian" # Knowledge base that works on top of markdown files
      "dynalist" # Outliner and list making app
      "anki" # Spaced repetition flashcard program

      # Utilities
      "ghostty" # GUI terminal (nixpkgs は darwin 非対応→cask。設定は modules/ghostty/home.nix)
      # "cmux" # 引退（Ghostty + herdr へ移行）。nix の管理対象から外す。cleanup="none" のため
      #        app 本体は自動削除されない → 消すなら手動 `brew uninstall --cask cmux`。戻すならこの行を復活
      # aerospace は nixpkgs 管理へ移行 (modules/apps/aerospace/home.nix 2026-07-08)。
      # 旧 cask は手動 `brew uninstall --cask aerospace`（quit してから）
      "raycast" # Productivity tool (HotKey: alt/option + space)
      "stats" # System monitor for the menu bar
      "gyazo" # Screenshot and sharing tool
      "whatsapp" # WhatsApp desktop client
      "caffeine" # Prevent Mac from sleeping
      "surfshark" # VPN service
      "handy" # Speech to text application
    ];
  };
}
