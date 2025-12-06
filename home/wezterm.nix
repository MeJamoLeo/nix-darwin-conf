{pkgs, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.wezterm;
    extraConfig = ''
      return {
        font_size = 20.0,
      }
    '';
  };
}
