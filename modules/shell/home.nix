{...}: {
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # home-manager の Ghostty zsh 統合は $GHOSTTY_RESOURCES_DIR が空でないかだけで
  # source するため、cmux.app 等が壊れたバンドルパスをその変数に入れると
  # "no such file or directory: .../ghostty-integration" で落ちる。無効化して
  # 下の initContent でファイル存在ガード付きに置き換える（cmux 引退後の耐性）。
  programs.ghostty.enableZshIntegration = false;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    # 旧 ~/.zprofile（Homebrew インストーラが書いた1行）の宣言化。
    # home-manager 25.11+ は zsh 有効時に ~/.zprofile を生成するため、
    # 管理外ファイルのままだと activation が clobber エラーで止まる。
    # dejima 等 homebrew の無いホストでも壊れないよう存在ガード付き。
    profileExtra = ''
      [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
    initContent = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      bindkey -e  # emacsモードを有効化（Ctrl+N, Ctrl+Pが使えるようになる）
      eval "$(direnv hook zsh)" # direnvを有効化, direnvは環境変数を管理するツール

      # Ghostty shell integration: 統合ファイルが実在する時だけ source する。
      # 本物の Ghostty では効き、壊れた GHOSTTY_RESOURCES_DIR（cmux バンドル等）では黙ってスキップ。
      if [[ -n "$GHOSTTY_RESOURCES_DIR" && -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
        source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
      fi
    '';
  };

  home.shellAliases = {
    k = "kubectl";

    urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
    urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

    cdsp = "claude --dangerously-skip-permissions";
  };
}
