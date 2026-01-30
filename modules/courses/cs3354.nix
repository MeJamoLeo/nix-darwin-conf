# CS 3354 - Homebrew packages (GUI apps)
# Import this in flake.nix modules list
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
