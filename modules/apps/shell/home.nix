{...}: {
  # ⚠ home.sessionVariables に**新しい変数を足した／値を変えた**ときの注意
  #   （2026-08-29 に NH_DARWIN_FLAKE 追加で踏んだ。pam_reattach と同じ構図で2度目）
  #
  #   生成される hm-session-vars.sh は冒頭でこうガードしている：
  #       if [ -n "''${__HM_SESS_VARS_SOURCED-}" ]; then return; fi
  #   この変数は **export される＝子プロセスに継承される**ので、switch より前に起動した
  #   長生きプロセス（herdr server / Ghostty / tmux）の配下では、新しいターミナルを
  #   開いても .zshenv/.zprofile が早期 return して**新しい変数が降りてこない**。
  #   ファイルにも .zshenv の参照先にも正しい値が入っているのに空に見えるので紛らわしい。
  #
  #   確認：  env -u __HM_SESS_VARS_SOURCED zsh -c 'echo $NEW_VAR'   ← ここでは取れる
  #   その場しのぎ（そのペインだけ新環境にする）：
  #       unset __HM_SESS_VARS_SOURCED
  #       source /etc/profiles/per-user/treo/etc/profile.d/hm-session-vars.sh
  #   恒久化：長生きプロセスを再起動する（herdr server を落とすと**その配下の全ペインが
  #   死ぬ**ので、作業が残っていないタイミングを選ぶこと）。
  #
  #   ★一般形：**長生きプロセスは、起動時点の環境を子孫に配り続ける。** 宣言的設定は
  #   「次に生まれるプロセス」にしか効かない。switch が緑でも既存プロセスは変わらない。
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
      # direnv の zsh フックは programs.direnv (modules/apps/core-packages/home.nix) が生成する

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
