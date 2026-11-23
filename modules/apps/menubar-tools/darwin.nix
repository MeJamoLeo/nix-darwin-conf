{...}: {
  # Casks, not nixpkgs: macOS 27 force-hides menu bar items of apps running outside /Applications
  # while Hidden Bar is collapsed, and nixpkgs' hidden-bar also predates the macOS 26/27 fixes.
  homebrew.casks = ["hiddenbar" "stats" "keepingyouawake"];

  # Hidden Bar cannot fold these away; they stay reachable from Control Center.
  system.defaults.controlcenter = {
    Sound = false;
    Bluetooth = false;
    Display = false;
  };
}
