{
  config,
  pkgs,
  ...
}: {
  xdg.configFile."yabai/yabairc".text = ''
    yabai -m config layout bsp
    yabai -m config auto_balance on
  '';

  xdg.configFile."skhd/skhdrc".text = ''
    cmd + alt - return : yabai -m window --toggle zoom-fullscreen
    hyper - p : ~/.local/bin/atcoder-mode
  '';

  home.file.".local/bin/atcoder-mode" = {
    source = ./../scripts/atcoder-mode.sh;
    executable = true;
  };
}
