{
  lib,
  username,
  pkgs,
  nixpkgs-stable,
  ...
}: let
  # unstable の git 2.54.0 は、長い unicode ファイル名を含む作業ツリーの untracked 走査で
  # SIGTRAP（バッファオーバーフローをスタック保護が検知）を起こす。hunk / git-crypt も
  # 内部で untracked 走査を呼ぶため巻き添えで落ちる。安定版(nixos-25.05)の git 2.50.1 は
  # 無傷なので git だけこれにピン留めする。2.54.x で修正されたら flake.nix の
  # nixpkgs-stable input ごと外す。詳細は flake.nix の nixpkgs-stable コメント参照。
  pkgsStable = nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in {
  # `programs.git` will generate the config file: ~/.config/git/config
  # to make git use this config file, `~/.gitconfig` should not exist!
  #
  #    https://git-scm.com/docs/git-config#Documentation/git-config.txt---global
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    rm -f ~/.gitconfig
  '';

  # allowed_signers を**生成**する（リポジトリに公開鍵を焼き込まない）。
  # このリポジトリは public なので、鍵の実体は宣言に入れず activation 時に
  # ~/.ssh から読む。公開鍵自体は秘密ではないが、鍵を差し替えたときに
  # 宣言と実体が乖離するのを避けたい（★複製は必ず乖離する）。
  # ~/.config/git/ は実ディレクトリで、home-manager が symlink しているのは
  # config だけなのでここに書いても衝突しない。
  home.activation.gitAllowedSigners = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # `run` は使わない：リダイレクトを付けると dry-run のエコー出力が
    # そのままファイルへ流れ込んでしまう。DRY_RUN を自分で見て分岐する。
    if [ -r "$HOME/.ssh/id_ed25519.pub" ] && [ -z "''${DRY_RUN:-}" ]; then
      mkdir -p "$HOME/.config/git"
      printf '%s namespaces="git" %s\n' \
        "55238651+MeJamoLeo@users.noreply.github.com" \
        "$(cat "$HOME/.ssh/id_ed25519.pub")" \
        > "$HOME/.config/git/allowed_signers"
    fi
  '';

  # git-crypt — 2026-08-29 に homebrew から nixpkgs へ移した（brew 版と同じ 0.8.0）。
  #
  # 移行の理由：**非対話 ssh で PATH に入らず、リモートからの vault 操作が落ちる**。
  # brew の PATH は `brew shellenv` を評価する ~/.zprofile 経由で張られるが、
  # `ssh host 'cmd'` はログインシェルを起こさないので /opt/homebrew/bin を見ない。
  # claude-obsidian の vault は .gitattributes で git-crypt filter を張っているため、
  # フィルタが見つからないと commit 自体が
  #     "git-crypt" clean: git-crypt: command not found
  #     fatal: <file>: clean filter 'git-crypt' failed
  # で失敗する（2026-08-29 に tanegashima への ssh で実際に踏んだ）。
  # nix 管理なら /etc/profiles/per-user/treo/bin に入り、非対話でも解決する。
  #
  # ここ（apps/git）に置くのは、git のフィルタとして動く＝ git の一部として扱うのが
  # 自然なため。上の SIGTRAP コメントでも git 本体と並べて言及している。
  #
  # ⚠ brew 版は宣言に無い（手で入れたもの）ので自動では消えない。PATH 優先順位で
  #   nix 版が勝つため実害は無いが、掃除するなら各機で `brew uninstall git-crypt`。
  home.packages = [pkgs.git-crypt];

  programs.git = {
    enable = true;
    # 上記コメント参照：unstable git 2.54.0 の untracked 走査 SIGTRAP 回避のため 2.50.1 に固定
    package = pkgsStable.git;
    lfs.enable = true;

    includes = [
      {
        # use diffrent email & name for work
        path = "~/work/.gitconfig";
        condition = "gitdir:~/work/";
      }
    ];

    # コミット署名 — GPG ではなく **SSH 署名**（2026-09-28）。
    #
    # 動機：RivoLink/leaf の PR #303 が「未署名なのでメンテナが再署名する」扱いになった。
    # git の user.name / user.email は自己申告なので、署名が無いと作者を検証できない。
    #
    # GPG(openpgp) ではなく ssh を選んだ理由：**鍵が既にある**。
    # ~/.ssh/id_ed25519 は github.com の認証で現に使っている鍵（~/.ssh/config に
    # github.com の Host エントリが無く、既定の id_ed25519 で `ssh -T` が通る）。
    # GPG を採ると鍵の生成・失効・バックアップという別ライフサイクルを1つ増やすことになる。
    # 秘密鍵は1本も存在しなかった（`gpg --list-secret-keys` が空）＝ openpgp 設定は
    # home-manager の既定値が出ていただけで、実際には一度も署名できていなかった。
    #
    # ⚠ GitHub 側に **signing key として別途登録**が必要（authentication key とは別枠。
    #   同じ公開鍵を2回登録する形になる）。未登録だと Verified が付かない。
    signing = {
      format = "ssh";
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };

    settings = {
      user = {
        name = "MeJamoLeo";
        email = "55238651+MeJamoLeo@users.noreply.github.com";
      };
      # ローカルで `git log --show-signature` を通すための信頼リスト。
      # GitHub 側の登録とは独立（こちらは自分のマシンでの検証用）。
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      alias = {
        # common aliases
        br = "branch";
        co = "checkout";
        st = "status";
        ls = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate";
        ll = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate --numstat";
        cm = "commit -m";
        ca = "commit -am";
        dc = "diff --cached";
        amend = "commit --amend -m";

        # aliases for submodule
        update = "submodule update --init --recursive";
        foreach = "submodule foreach";
      };
    };
  };
}
