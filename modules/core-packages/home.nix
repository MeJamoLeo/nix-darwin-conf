{pkgs, ...}: {
  home.packages = with pkgs; [
    # build / task runners
    just # Command runner (Justfile)
    tmux # Terminal multiplexer
    herdr # tmux ライクなエージェント対応マルチプレクサ（flake overlay 由来: flake.nix 参照）
    # online-judge-tools は modules/cp/tools/home.nix がラッパー付きで提供する
    # （`oj test` 成功でダッシュボード STOPWATCH を臨戦態勢にするマーカーを書く）

    # archives
    zip
    xz
    unzip

    # utils
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processer https://github.com/mikefarah/yq
    fzf # A command-line fuzzy finder

    # CLI dev tools (Homebrew から移行 2026-07-08)。dejima は homebrew ごと
    # 無効 (flake.nix) なので brew 管理だと headless 機に入らない。nix 化で
    # 全ホストに flake.lock 固定の同一バージョンが届き、quarantine とも無縁。
    gh # github cli
    lazygit # Git terminal UI
    direnv # Tool for managing environment variables per directory (hook は shell.nix)
    wget # Download tool

    nmap # A utility for network discovery and security auditing

    google-clasp

    # misc
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    caddy
    gnupg

    # productivity
    glow # markdown previewer in terminal
    fastfetch # system information tool

    # compilers
    gcc
    go
    nodejs
    tree-sitter

    # GUI apps (nixpkgs 製。~/Applications/Home Manager Apps/ に .app が入る。
    # Dock の persistent-apps もそのパスを参照: modules/macos-defaults/darwin.nix)
    zed-editor # High-performance collaborative code editor
  ];

  programs = {
    # A modern replacement for ‘ls’
    # useful in bash/zsh prompt, not in nushell.
    eza = {
      enable = true;
      git = true;
      icons = "auto";
      enableZshIntegration = true;
    };

    # terminal file manager
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        manager = {
          show_hidden = true;
          sort_dir_first = true;
        };
      };
    };

    # skim provides a single executable: sk.
    # Basically anywhere you would want to use grep, try sk instead.
    skim = {
      enable = true;
      enableBashIntegration = true;
    };
  };
}
