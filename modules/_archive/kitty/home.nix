{ config, lib, pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 12;
      background_opacity = "0.5";
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

  # Linux only: drop-down terminal (kitten quick-access-terminal), Alt+` in niri. It overlaps other
  # windows, so it is more opaque than the normal terminal (0.5 let the page below show through).
  xdg.configFile."kitty/quick-access-terminal.conf" = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    text = ''
      edge top
      lines 20
      background_opacity 0.85
      margin_left 120
      margin_right 120
    '';
  };

  xdg.configFile."kitty/ssh.conf".text = ''
    hostname *
    env LANG=ja_JP.UTF-8
    env LC_ALL=ja_JP.UTF-8
  '';
}
