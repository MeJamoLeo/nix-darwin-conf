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

    settings = {
      user = {
        name = "MeJamoLeo";
        email = "55238651+MeJamoLeo@users.noreply.github.com";
      };
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
