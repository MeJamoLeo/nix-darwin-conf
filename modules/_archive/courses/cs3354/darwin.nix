# CS 3354 - Homebrew packages (GUI apps)
# profiles/mac-workstation.nix から import される
{...}: {
  homebrew = {
    casks = [
      "gitkraken"
      "slack"
      "visual-studio-code"
      "visualvm"
    ];
  };
}
