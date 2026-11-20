{ config, lib, pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    # 配色は modules/custom/desktop-theme（Mod+Shift+T）が include で差し込む（2026-11-20）。
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 12;
      background_opacity = "0.5"; # 2026-11-19: 0.85 → 0.5（壁紙を半分透かす。文字は不透明のまま）
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

  # Linux（niri）だけ：上から降りてくる端末（kitten quick-access-terminal）。Mac の OmniWM の
  # Option+` （toggleQuakeTerminal）と同じ役。Alt+` で出し入れする（キーは modules/apps/niri）。
  # 配色・フォントは kitty.conf をそのまま引き継ぐ。ここは差分だけ。
  xdg.configFile."kitty/quick-access-terminal.conf" = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    text = ''
      edge top
      lines 20
      background_opacity 0.5
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
