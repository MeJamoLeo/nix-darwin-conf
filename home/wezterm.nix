{pkgs, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.wezterm;
    extraConfig = ''
      return {
        font_size = 20.0,
        color_scheme = 'Kasugano (terminal.sexy)',
        window_background_opacity = 0.8,
        macos_window_background_blur = 20,
        window_decorations = "RESIZE",
        show_tabs_in_tab_bar = true,
        hide_tab_bar_if_only_one_tab = true,
        window_frame = {
          inactive_titlebar_bg = "none",
          active_titlebar_bg = "none"
        }
      }
    '';
  };
}
