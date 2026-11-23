{...}: {
  # Cask, not nixpkgs: nixpkgs' hidden-bar is 1.10, which predates the macOS 26/27 menu bar fixes.
  homebrew.casks = ["hiddenbar"];
}
