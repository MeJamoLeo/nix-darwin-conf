# CS 3354 - Development environment
# Import this in home/default.nix imports list
{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    git
    gradle
  ];

  programs.java = {
    enable = true;
    package = pkgs.jdk21;
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
    mkdir -p "$HOME/txst/CS3354"
  '';

  home.activation.cs3354-reminder = lib.hm.dag.entryAfter ["cs3354-setup"] ''
    missing=""
    if ! /opt/homebrew/bin/code --list-extensions 2>/dev/null | grep -qi "vscjava.vscode-java-pack"; then
      missing="$missing\n  - Extension Pack for Java"
    fi
    if ! /opt/homebrew/bin/code --list-extensions 2>/dev/null | grep -qi "oracle-labs-graalvm.visualvm-vscode"; then
      missing="$missing\n  - VisualVM for VS Code"
    fi
    if [ -n "$missing" ]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "CS 3354: Missing VSCode extensions:"
      printf "$missing\n"
      echo ""
      echo "Git: Repositories in ~/txst/ will use TxState credentials"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
  '';
}
