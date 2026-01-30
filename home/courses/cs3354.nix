# CS 3354 - Development environment
# Import this in home/default.nix imports list
{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    git
    jdk21
    gradle
  ];

  home.sessionVariables = {
    JAVA_HOME = "${pkgs.jdk21}/lib/openjdk";
  };

  # TxState 用の git 設定ファイル
  home.file.".gitconfig-txst".text = ''
    [user]
      name = Reo Tajiri
      email = kif33@txstate.edu
  '';

  # ~/txst/ 以下のリポジトリで自動的に TxState 用設定を適用
  programs.git.includes = [
    {
      path = "~/.gitconfig-txst";
      condition = "gitdir:~/txst/";
    }
  ];

  home.activation.cs3354-setup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/txst"
  '';

  home.activation.cs3354-reminder = lib.hm.dag.entryAfter ["cs3354-setup"] ''
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CS 3354: VSCode extensions must be installed manually:"
    echo "  - Extension Pack for Java"
    echo "  - VisualVM for VS Code"
    echo ""
    echo "Git: Repositories in ~/txst/ will use TxState credentials"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  '';
}
