# niri（Wayland のタイル型コンポジタ）を中心にした x1nano のデスクトップ一式。
# ログインは greetd + tuigreet（TUI）。Enter で入るのは素の zsh で、GUI は
# `niri-session` と打ったとき（または tuigreet の F3 で niri を選んだとき）だけ動く
# ＝電池を食う GUI を常駐させない（2026-10-23 の決定）。
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
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${pkgs.zsh}/bin/zsh --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
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
    TERMINAL = "kitty";
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
