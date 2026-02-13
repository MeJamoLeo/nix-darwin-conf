{...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    initContent = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      bindkey -e  # emacsモードを有効化（Ctrl+N, Ctrl+Pが使えるようになる）
      eval "$(direnv hook zsh)" # direnvを有効化, direnvは環境変数を管理するツール
    '';
  };

  home.shellAliases = {
    k = "kubectl";

    urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
    urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

    cdsp = "claude --dangerously-skip-permissions";
  };
}
