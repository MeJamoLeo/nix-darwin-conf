{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    # Fixed palette that matches DankMaterialShell's Material 3 dark surface.
    # Not driven by matugen — the shell can retheme freely without kitty
    # colors drifting under a long-lived terminal session.
    themeFile = "Catppuccin-Mocha";
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 12;
      background_opacity = "0.85";
      confirm_os_window_close = 0;
      enable_audio_bell = "no";
      allow_remote_control = "yes";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";
      # niri is a tiling compositor and DMS already shows the focused
      # window's title in its top bar — the client-side kitty titlebar
      # (app-id + title strip) is redundant, so hide it.
      hide_window_decorations = "yes";
    };
    keybindings = {
      "ctrl+shift+t" = "new_tab_with_cwd";
      "ctrl+shift+n" = "new_os_window_with_cwd";
    };
  };

  xdg.configFile."kitty/ssh.conf".text = ''
    hostname *
    env LANG=ja_JP.UTF-8
    env LC_ALL=ja_JP.UTF-8
  '';
}
