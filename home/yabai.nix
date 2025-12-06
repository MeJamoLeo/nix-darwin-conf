{
  config,
  lib,
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

  home.activation.startBrewYabaiSkhd = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    if command -v brew >/dev/null 2>&1; then
      # Formulaはplistを持たないため brew services start は失敗する。
      # 代わりに公式の --start-service を使って launchd に登録する。
      if HOMEBREW_NO_AUTO_UPDATE=1 brew list --formula yabai >/dev/null 2>&1; then
        if command -v yabai >/dev/null 2>&1; then
          yabai --start-service || true
        fi
      fi
      if HOMEBREW_NO_AUTO_UPDATE=1 brew list --formula skhd >/dev/null 2>&1; then
        if command -v skhd >/dev/null 2>&1; then
          skhd --start-service || true
        fi
      fi
    else
      echo "brew not found; skip starting yabai/skhd services"
    fi
  '';
}
