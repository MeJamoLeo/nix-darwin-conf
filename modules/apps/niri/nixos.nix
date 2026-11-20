# niri（Wayland のタイル型コンポジタ）を中心にした x1nano のデスクトップ一式。
# greetd + tuigreet (TUI); logging in starts niri directly.
# F3 in tuigreet picks a plain zsh instead (no resident GUI, saves battery).
{
  config,
  pkgs,
  username,
  ...
}: {
  programs.niri.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session = {
      # --remember-session は付けない：/var/cache/tuigreet の記憶が --cmd に勝ってしまい、
      # 宣言した既定が「最後に選んだもの」に負けるため。
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
      user = username;
    };
  };

  # X11 アプリ（VirtualBox の Qt UI 等）用。niri の spawn-at-startup が起動する。
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    papirus-icon-theme
    adwaita-icon-theme
  ];

  environment.sessionVariables = {
    DISPLAY = ":0"; # xwayland-satellite の既定ディスプレイ
    WLR_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1"; # Electron/Chromium 系を Wayland ネイティブで
    TERMINAL = "ghostty";
    TMUX_TMPDIR = "$XDG_RUNTIME_DIR";
  };

  # ファイラ（Thunar）とサムネイル・ゴミ箱・リムーバブル。
  programs.thunar.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.xserver.desktopManager.runXdgAutostartIfNone = true;

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig = {
    enable = true;
    antialias = true;
    hinting = {
      enable = true;
      style = "slight";
    };
    subpixel.lcdfilter = "light";
    defaultFonts.monospace = ["JetBrainsMono Nerd Font"];
  };
}
