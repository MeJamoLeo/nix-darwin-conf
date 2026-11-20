{
  config,
  lib,
  pkgs,
  ...
}:
##########################################################################
#
#  desktop-theme — switch the x1nano colour scheme (DMS, niri borders, Ghostty) with Mod+Shift+T.
#  Themes are kitty-format files from kitty-themes + iTerm2-Color-Schemes; ayu Dark uses the hand-tuned
#  ./ayu-dark.dms.json. nvim and the browser do not follow (they need per-theme plugin support).
#
##########################################################################
let
  kittyThemes = "${pkgs.kitty-themes}/share/kitty-themes/themes";
  extraThemes = import ./extra-themes.nix {inherit pkgs;};
  confOf = n: extraThemes.${n} or "${kittyThemes}/${n}.conf";

  # Dark themes only: the terminal is 50% translucent, so light ones are hard to read.
  themeNames = [
    "ayu"
    "ayu_mirage"
    "Catppuccin-Mocha"
    "Catppuccin-Macchiato"
    "Catppuccin-Frappe"
    "tokyo_night_night"
    "tokyo_night_storm"
    "tokyo_night_moon"
    "gruvbox-dark"
    "gruvbox-dark-hard"
    "GruvboxMaterialDarkMedium"
    "Nord"
    "kanagawa"
    "kanagawa_dragon"
    "rose-pine"
    "rose-pine-moon"
    "everforest_dark_medium"
    "everforest_dark_hard"
    "Dracula"
    "OneDark-Pro"
    "Doom_One"
    "MaterialDark"
    "Solarized_Dark"
    "GitHub_Dark"
    "GitHub_Dark_Dimmed"
    "Monokai_Classic"
    "Nightfox"
    "night_owl"
    "moonfly"
    "Vesper"
    "Carbonfox"
    "Duskfox"
    "Terafox"
    "Nordfox"
    "Iceberg_Dark"
    "Kanagawabones"
    "Midnight_Tundra"
    "Sonoran_Blue_Hour"
    "Kanso_Ink"
    "Everblush"
    "Onenord"
    "Oceanic_Next"
    "OneDark"
    "OneHalfDark"
    "Atom"
    "VSCode_Dark"
    "OceanicMaterial"
    "Tomorrow_Night"
    "Tomorrow_Night_Eighties"
    "Zenburn"
    "Modus_Vivendi"
    "PaperColor_dark"
    "Cobalt2"
    "solarized_osaka_dark"
    "sonokai-sushia"
    "flexoki_dark"
    "nightfly"
    "Jellybeans"
  ];

  themes = pkgs.runCommand "desktop-themes" {nativeBuildInputs = [pkgs.python3];} ''
    mkdir -p $out
    ${lib.concatMapStringsSep "\n" (n: ''
        mkdir -p "$out/${n}"
        cp ${confOf n} "$out/${n}/kitty.conf"
        python3 ${./gen-dms-theme.py} ${confOf n} "$out/${n}/dms.json" "${n}"
        python3 ${./gen-ghostty-theme.py} ${confOf n} "$out/${n}/ghostty.conf"
      '')
      themeNames}
    cp ${./ayu-dark.dms.json} "$out/ayu/dms.json"
    printf '%s\n' ${lib.escapeShellArgs themeNames} > $out/list
    python3 ${./list-swatches.py} $out ${lib.escapeShellArgs themeNames} > $out/list-swatches
  '';

  stateDir = "${config.xdg.stateHome}/desktop-theme";

  # Write a temp file and mv it: a plain `cat >` is briefly empty and DMS shows an "Invalid JSON format" toast.
  apply = ''
    mkdir -p "${stateDir}"
    for f in dms.json ghostty.conf; do
      cp "${themes}/$name/$f" "${stateDir}/.$f.tmp"
      chmod 644 "${stateDir}/.$f.tmp"
      mv -f "${stateDir}/.$f.tmp" "${stateDir}/$f"
    done
    printf '%s\n' "$name" > "${stateDir}/name"
  '';

  themeSwitch = pkgs.writeShellApplication {
    name = "theme-switch";
    runtimeInputs = with pkgs; [fzf fastfetch procps coreutils gnugrep];
    text = ''
      if [ $# -gt 0 ]; then
        name=$1
        [ -d "${themes}/$name" ] || { echo "unknown theme: $name" >&2; exit 1; }
        ${apply}
        # Reload open Ghostty windows. The name is '.ghostty-wrappe' because the process name is cut at 15 chars.
        pkill -USR2 -x '.ghostty-wrappe' || true
        exit 0
      fi

      # Keep focus unbound until the list has loaded and moved to the current theme; start:pos alone
      # previewed the first entry (ayu).
      self=$(readlink -f "$0")
      orig=$(cat "${stateDir}/name" 2>/dev/null || echo ayu)
      pos=$(grep -n -x -F "$orig" ${themes}/list | cut -d: -f1 || true)
      sel=$(fzf --ansi --delimiter '\t' --with-nth 1,2 --no-sort --layout reverse --cycle \
              --prompt 'theme> ' \
              --header "Up/Down: preview live   Enter: keep   Esc: revert to $orig" \
              --bind "start:unbind(focus)" \
              --bind "load:pos(''${pos:-1})+rebind(focus)" \
              --bind "focus:execute-silent($self {2})" \
              --preview 'fastfetch --pipe false' \
              --preview-window 'right,62%,border-left' \
              < ${themes}/list-swatches | cut -f2 || true)
      if [ -z "$sel" ]; then
        "$self" "$orig"
      fi
    '';
  };
in {
  home.packages = [themeSwitch];

  home.activation.desktopTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    name=$(cat "${stateDir}/name" 2>/dev/null || true)
    [ -n "$name" ] && [ -d "${themes}/$name" ] || name=ayu
    ${apply}
  '';

  programs.dank-material-shell.settings = {
    currentThemeName = "custom";
    customThemeFile = "${stateDir}/dms.json";
  };

  # '?' makes a missing file non-fatal (before the first switch).
  programs.ghostty.settings.config-file = "?${stateDir}/ghostty.conf";

  # theme-switch is called by absolute store path: the /etc/profiles PATH only updates on nixos-rebuild,
  # so a home-manager-only switch would not find it.
  programs.niri.settings.binds."Mod+Shift+T" = {
    # +new-window asks the resident Ghostty (a fresh process takes 1.9 s). Same app-id, so the
    # floating rule matches on title.
    action.spawn = ["ghostty" "+new-window" "--title=Theme Picker" "-e" "${themeSwitch}/bin/theme-switch"];
    hotkey-overlay.title = "Theme Picker";
  };
  programs.niri.settings.window-rules = [
    {
      matches = [{
        app-id = "^com\\.mitchellh\\.ghostty$";
        title = "^Theme Picker$";
      }];
      open-floating = true;
      default-column-width.fixed = 1400;
      default-window-height.fixed = 820;
    }
  ];
}
