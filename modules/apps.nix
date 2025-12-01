{pkgs, ...}: {
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
  environment.systemPackages = with pkgs; [
    # neovim     # Terminal-based text editor (nixvim manages nvim)
    git # Version control system
    just # Command runner for project-specific commands (use Justfile to simplify nix-darwin's commands)
  ];
  environment.variables.EDITOR = "nvim";

  # TODO To make this work, homebrew need to be installed manually, see https://brew.sh
  #
  # The apps installed by homebrew are not managed by nix, and not reproducible!
  # But on macOS, homebrew has a much larger selection of apps than nixpkgs, especially for GUI apps!
  homebrew = {
    enable = true;

    # onActivation = {
    #   autoUpdate = true; # Fetch the newest stable branch of Homebrew's git repo
    #   upgrade = true; # Upgrade outdated casks, formulae, and App Store apps
    #   # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
    #   cleanup = "uninstall";
    # };

    # Applications to install from Mac App Store using mas.
    # You need to install all these Apps manually first so that your apple account have records for them.
    # otherwise Apple Store will refuse to install them.
    # For details, see https://github.com/mas-cli/mas
    masApps = {
      # TODO Feel free to add your favorite apps here.

      Xcode = 497799835; # Apple's IDE for macOS/iOS development
      DisplayMenu = 549083868; # Menu bar tool for display management
    };

    taps = [
      "homebrew/services"
    ];

    # `brew install` - Command line tools
    brews = [
      "curl" # HTTP client (don't install via nixpkgs, not working well on macOS!)
      "direnv" # Tool for managing environment variables per directory
      # "neovim"  # Terminal-based text editor (nixvim manages nvim)
      "texlive" # LaTeX distribution
      "wget" # Download tool
    ];

    # `brew install --cask` - GUI applications
    casks = [
      # Browsers
      "google-chrome" # Web browser
      "brave-browser" # Privacy-focused web browser

      # Development
      "cursor" # AI-powered code editor
      "cursor-cli" # Cursor CLI wrapper
      "visual-studio-code" # Code editor

      # Communication & Meetings
      "discord" # Chat and voice communication platform
      "zoom" # Video conferencing

      # Media
      "obs" # Open Broadcaster Software for recording/streaming
      "iina" # Modern video player
      "steam" # Gaming platform

      # Productivity & Organization
      "obsidian" # Knowledge base that works on top of markdown files
      "dynalist" # Outliner and list making app
      "notion" # All-in-one workspace
      "anki" # Spaced repetition flashcard program

      # Utilities
      "raycast" # Productivity tool (HotKey: alt/option + space)
      "stats" # System monitor for the menu bar
      "gyazo" # Screenshot and sharing tool
      "amethyst" # Tiling window manager
      "whatsapp" # WhatsApp desktop client
      "caffeine" # Prevent Mac from sleeping

      # LaTeX
      "mactex" # MacTeXのGUIインストーラー
    ];
  };
}
