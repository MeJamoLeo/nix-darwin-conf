{
  config,
  lib,
  pkgs,
  ...
}:
##########################################################################
#
#  desktop-theme — x1nano（niri＋DMS）の配色を Mod+Shift+T で切り替える（2026-11-20）。
#
#  一覧は kitty 同梱のテーマ集から人気の 30 個（明るい物も含む）。選ぶと
#    - DMS（バー・ランチャー・コントロールセンター）と niri の枠色（DMS が書き出す）
#    - kitty（開いている端末も load-config で即反映）
#  が切り替わる。DMS 用の配色は kitty のテーマから ./gen-dms-theme.py で自動で作る。
#  ayu Dark だけは手で合わせた ./ayu-dark.dms.json を使う（2026-11-19 に作った物）。
#
#  選んだ配色は ~/.local/state/desktop-theme/ に置く（name / dms.json / kitty.conf）。
#  DMS の customThemeFile と kitty の include がここを指す。switch では選択を上書きせず、
#  中身だけ今の store の版へ書き直す（未選択・候補から消えた物なら ayu に戻す）。
#  dms.json は symlink ではなく中身を上書きする — DMS は inotify でファイルを見ているので、
#  symlink の張り替え（rename）だと監視が外れて反映されない。
#
#  nvim とブラウザは追従しない（テーマごとのプラグイン対応が要るので別段）。
#
##########################################################################
let
  kittyThemes = "${pkgs.kitty-themes}/share/kitty-themes/themes";

  # 表示名 = kitty-themes のファイル名（.conf 抜き）。並びがそのまま一覧の順。
  themeNames = [
    "ayu"
    "ayu_mirage"
    "ayu_light"
    "Catppuccin-Mocha"
    "Catppuccin-Macchiato"
    "Catppuccin-Frappe"
    "Catppuccin-Latte"
    "tokyo_night_night"
    "tokyo_night_storm"
    "tokyo_night_day"
    "gruvbox-dark"
    "gruvbox-light"
    "GruvboxMaterialDarkMedium"
    "Nord"
    "kanagawa"
    "kanagawa_dragon"
    "rose-pine"
    "rose-pine-moon"
    "rose-pine-dawn"
    "everforest_dark_medium"
    "everforest_light_medium"
    "Dracula"
    "OneDark-Pro"
    "Solarized_Dark"
    "Solarized_Light"
    "GitHub_Dark"
    "GitHub_Light"
    "Monokai_Classic"
    "Nightfox"
    "night_owl"
  ];

  themes = pkgs.runCommand "desktop-themes" {nativeBuildInputs = [pkgs.python3];} ''
    mkdir -p $out
    ${lib.concatMapStringsSep "\n" (n: ''
        mkdir -p "$out/${n}"
        cp ${kittyThemes}/${n}.conf "$out/${n}/kitty.conf"
        python3 ${./gen-dms-theme.py} ${kittyThemes}/${n}.conf "$out/${n}/dms.json" "${n}"
      '')
      themeNames}
    cp ${./ayu-dark.dms.json} "$out/ayu/dms.json"
    printf '%s\n' ${lib.escapeShellArgs themeNames} > $out/list
  '';

  stateDir = "${config.xdg.stateHome}/desktop-theme";

  # 選んだ名前のファイルを state へ書く（中身の上書き。上のコメント参照）。
  apply = ''
    mkdir -p "${stateDir}"
    cat "${themes}/$name/dms.json" > "${stateDir}/dms.json"
    cat "${themes}/$name/kitty.conf" > "${stateDir}/kitty.conf"
    printf '%s\n' "$name" > "${stateDir}/name"
  '';

  themeSwitch = pkgs.writeShellApplication {
    name = "theme-switch";
    runtimeInputs = with pkgs; [wofi kitty coreutils];
    text = ''
      cur=$(cat "${stateDir}/name" 2>/dev/null || true)
      name=''${1:-$(wofi --dmenu --prompt "Theme (now: ''${cur:-none})" --cache-file /dev/null < ${themes}/list)}
      [ -n "$name" ] || exit 0
      [ -d "${themes}/$name" ] || { echo "unknown theme: $name" >&2; exit 1; }
      ${apply}
      # 開いている kitty に読み直させる（listen_on は modules/apps/kitty/home.nix）。
      for s in /tmp/kitty-*; do
        [ -S "$s" ] && kitty @ --to "unix:$s" load-config >/dev/null 2>&1 || true
      done
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

  programs.kitty.extraConfig = ''
    include ${stateDir}/kitty.conf
  '';

  programs.niri.settings.binds."Mod+Shift+T" = {
    # store の絶対パスで呼ぶ（PATH の /etc/profiles は nixos-rebuild でしか更新されないので、
    # home-manager だけ当てた状態でも動くように）。
    action.spawn = ["${themeSwitch}/bin/theme-switch"];
    hotkey-overlay.title = "Theme Picker";
  };
}
