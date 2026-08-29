{
  config,
  pkgs,
  hunk,
  ...
}: {
  home.packages = with pkgs; [
    # build / task runners
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
    hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk # エージェント製差分レビュー用ターミナル差分ビューア（flake input: flake.nix 参照）
    # direnv は下の programs.direnv で宣言（nix-direnv 統合込み）
    wget # Download tool

    nmap # A utility for network discovery and security auditing
    gitleaks # git 履歴/ファイルの秘密情報（APIキー等）スキャナ

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
    # nix コマンドのラッパー。**Justfile の後継**（2026-08-29 に just を撤去）。
    #
    # 旧 Justfile はテンプレ残渣で（導入コミット 670a7d8 に flake ごと一括流入・
    # 選択の記録が無い）、かつ `just darwin` は**リポジトリ内でしか打てない**＝
    # 「操作の前に cd」という日常の摩擦そのものだった。nh は flake の在処を
    # 環境変数で持つので、どのディレクトリからでも動く。
    #
    # `darwinFlake` は NH_DARWIN_FLAKE を張るだけでなく、nh のバージョンを見て
    # 4.0.0 未満なら旧名 FLAKE に切り替える分岐まで持っている（手書き env var では
    # 再現できない）。値は my.forgeDir 由来＝$FORGE と同じ単一源
    # （modules/base/forge/home.nix）。
    #
    # 移行後の対応：
    #   just darwin        → nh darwin switch      （ホスト名は nh が自動解決）
    #   just darwin-debug  → nh darwin switch -- --show-trace
    #   just clean / gc    → 下の clean.enable で launchd 定期実行に格上げ
    #   just up / upp      → nix flake update [input]
    #   just fmt           → nix fmt .
    #   just history / repl / gcroot → 代替なしで廃止（使用実績なし）
    #
    # 逃げ道：nh が壊れたら
    #   sudo darwin-rebuild switch --flake "$NH_DARWIN_FLAKE#$(hostname -s)"
    nh = {
      enable = true;
      darwinFlake = "${config.my.forgeDir}/nix-darwin-conf";

      # 旧 Justfile の clean/gc レシピ（手で打つ・打った記憶がない）を定期実行へ。
      # darwin では launchd.agents.nh-clean が生える。
      #
      # ⚠⚠ extraArgs は **`--flag=value` の1トークンで書くこと**（2026-08-29 に踏んだ）。
      #   home-manager の programs.nh は darwin で
      #     ProgramArguments = [ nh clean user ] ++ lib.optional (extraArgs != "") extraArgs
      #   と **文字列をまるごと配列要素1個** にする。launchd はシェルを挟まないので
      #   空白で分割されず、`nh clean user '--keep-since 7d --keep 5'` という
      #   1引数の呼び出しになって
      #     error: unexpected argument '--keep-since 7d --keep 5' found
      #   で**毎週静かに失敗する**。Linux 側は ExecStart で `clean user ''${extraArgs}` と
      #   シェル展開されるため同じ値が動く＝ OS 差のある上流バグ（option の example も
      #   "--keep 5 --keep-since 3d" と空白区切りを推奨してしまっている）。
      #   `--keep-since=7d` なら1トークンなのでクォートされても壊れない（実測確認済み）。
      #   複数フラグを渡したくなったら splitString 相当の回避が要る。
      # ⚠ nix.gc.automatic と併用すると警告が出る（モジュールが検出する）。
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep-since=7d";
      };
    };

    # ディレクトリ単位の環境変数管理。nix-direnv 統合で flake devShell を
    # 高速キャッシュ＆GC ルート固定。enable が direnv 本体＋zsh フック＋
    # ~/.config/direnv/direnvrc（nix-direnv を source）を宣言的に生成するので、
    # 旧 shell/home.nix の手動 `direnv hook zsh` と手書き direnvrc は不要になった。
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

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
      # home-manager 26.05 で default が "yy" → "y" に変わる予定。muscle memory
      # 保護のため "yy" を明示継続（1文字 y は yes と衝突しがちで危険）。
      shellWrapperName = "yy";
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
