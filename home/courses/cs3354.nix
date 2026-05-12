# CS 3354 - Software Engineering 開発環境
# TxState 用 git identity は home/school/txst.nix を参照
{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    gradle
  ];

  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  home.activation.cs3354 = lib.hm.dag.entryAfter ["txst-setup"] ''
    mkdir -p "$HOME/txst/CS3354"

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
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
  '';
}
