{pkgs, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.wezterm;
  };
}
