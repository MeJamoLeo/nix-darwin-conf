# niri（Wayland のタイル型コンポジタ）を中心にした x1nano のデスクトップ一式。
# greetd + DMS Greeter; logging in starts niri.
{
  config,
  pkgs,
  username,
  dms-greeter,
  ...
}: {
  imports = [dms-greeter.nixosModules.default];

  programs.niri.enable = true;

  # Runs as the default `greeter` user. Plain zsh is still reachable from another TTY.
  programs.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = config.users.users.${username}.home;
  };

  # X11 アプリ（VirtualBox の Qt UI 等）用。niri の spawn-at-startup が起動する。
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    papirus-icon-theme
    adwaita-icon-theme
  ];

  environment.sessionVariables = {
    # Do not set DISPLAY here: pam_env hands it to the greeter's niri, which then starts nested and crashes.
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
