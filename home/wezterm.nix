{pkgs, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.wezterm;
    extraConfig = ''
      local wezterm = require 'wezterm'
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
        },
        keys = {
          { key = 'd', mods = 'CMD', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
          { key = 'd', mods = 'CMD|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
          { key = 'w', mods = 'CMD', action = wezterm.action.CloseCurrentPane { confirm = true } },
          { key = '\\', mods = 'CMD', action = wezterm.action.PaneSelect },
          { key = 'h', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Left', 5 } },
          { key = 'l', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Right', 5 } },
          { key = 'k', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Up', 5 } },
          { key = 'j', mods = 'CMD|CTRL', action = wezterm.action.AdjustPaneSize { 'Down', 5 } },
          { key = 's', mods = 'CMD|CTRL', action = wezterm.action.PaneSelect { mode = 'SwapWithActive' } },
          { key = 'c', mods = 'CMD|CTRL', action = wezterm.action.ActivateCopyMode },
          { key = 'l', mods = 'CMD|SHIFT', action = wezterm.action.ShowLauncherArgs { flags = 'DOMAINS|TABS|LAUNCH_MENU_ITEMS' } },
        },
      }
    '';
  };
}
