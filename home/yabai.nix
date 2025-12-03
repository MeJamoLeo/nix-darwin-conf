{
  config,
  pkgs,
  ...
}: {
  # let
  #   atcoderMode = pkgs.writeShellScriptBin "atcoder-mode" ''
  #     #!/usr/bin/env bash
  #     # Placeholder for the previous AtCoder layout helper.
  #     # Restore the original script here when the orchestrated setup is needed again.
  #   '';
  # in
  home.packages = [
    pkgs.yabai
    pkgs.skhd
    # pkgs.jq # Required if the atcoderMode helper is restored.
    # atcoderMode # Bring back when re-enabling the orchestrated layout.
  ];

  xdg.configFile."yabai/yabairc".text = ''
    yabai -m config layout bsp
    yabai -m config auto_balance on
    # yabai -m config external_bar all:0:0
    # yabai -m config focus_follows_mouse autoraise
    # yabai -m config mouse_follows_focus off
    # yabai -m config split_ratio 0.50
    # yabai -m config window_placement second_child
    # yabai -m rule --add app="^Karabiner-Elements$" manage=off
    # yabai -m rule --add app="^System Settings$" manage=off
  '';

  xdg.configFile."skhd/skhdrc".text = ''
    cmd + alt - return : yabai -m window --toggle zoom-fullscreen
    # hyper - p : ${config.home.profileDirectory}/bin/atcoder-mode
  '';

  launchd.agents = {
    yabai = {
      enable = true;
      config = {
        ProgramArguments = [ "${config.home.profileDirectory}/bin/yabai" ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables = {
          PATH = "${config.home.profileDirectory}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          YABAI_CONFIG_DIR = "${config.home.homeDirectory}/.config/yabai";
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/yabai.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/yabai.log";
      };
    };

    skhd = {
      enable = true;
      config = {
        ProgramArguments = [
          "${config.home.profileDirectory}/bin/skhd"
          "-c"
          "${config.home.homeDirectory}/.config/skhd/skhdrc"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables = {
          PATH = "${config.home.profileDirectory}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/skhd.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/skhd.log";
      };
    };
  };
}
