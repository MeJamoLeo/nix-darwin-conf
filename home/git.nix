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
      # TODO replace with your own name & email
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

    # signing = {
    #   key = "xxx";
    #   signByDefault = true;
    # };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.features = "side-by-side";
  };
}
