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
#  一覧は kitty 同梱のテーマ集から人気のダーク系 30 個。選ぶと
#    - DMS（バー・ランチャー・コントロールセンター）と niri の枠色（DMS が書き出す）
#    - kitty（開いている端末も load-config で即反映）
#  が切り替わる。DMS 用の配色は kitty のテーマから ./gen-dms-theme.py で自動で作る。
#  ayu Dark だけは手で合わせた ./ayu-dark.dms.json を使う（2026-11-19 に作った物）。
#
#  選んだ配色は ~/.local/state/desktop-theme/ に置く（name / dms.json / kitty.conf）。
#  DMS の customThemeFile と kitty の include がここを指す。switch では選択を上書きせず、
#  中身だけ今の store の版へ書き直す（未選択・候補から消えた物なら ayu に戻す）。
#  dms.json は store への symlink にせず、実ファイルを mv で置き換える（下の apply）。
#
#  nvim とブラウザは追従しない（テーマごとのプラグイン対応が要るので別段）。
#
##########################################################################
let
  kittyThemes = "${pkgs.kitty-themes}/share/kitty-themes/themes";

  # 表示名 = kitty-themes のファイル名（.conf 抜き）。並びがそのまま一覧の順。
  # 2026-11-20: ダーク系だけ 30 個（明るい物は外した。端末を 50% 透かしているので読みにくい）。
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
    python3 ${./list-markup.py} $out ${lib.escapeShellArgs themeNames} > $out/list-markup
  '';

  stateDir = "${config.xdg.stateHome}/desktop-theme";

  # 選んだ名前のファイルを state へ書く。一時ファイルに書いてから mv で置き換える
  # （2026-11-20：`cat >` だといったん空になった瞬間を DMS が読み「Invalid JSON format」の
  # トーストが出た。mv の置き換えでも DMS は追従することを実機で確認済み）。
  apply = ''
    mkdir -p "${stateDir}"
    for f in dms.json kitty.conf; do
      cp "${themes}/$name/$f" "${stateDir}/.$f.tmp"
      chmod 644 "${stateDir}/.$f.tmp"
      mv -f "${stateDir}/.$f.tmp" "${stateDir}/$f"
    done
    printf '%s\n' "$name" > "${stateDir}/name"
  '';

  themeSwitch = pkgs.writeShellApplication {
    name = "theme-switch";
    runtimeInputs = with pkgs; [wofi kitty coreutils gawk];
    text = ''
      cur=$(cat "${stateDir}/name" 2>/dev/null || true)
      # 一覧は色見本つき（list-markup.py）。選んだ行の最後の語がテーマ名。
      name=''${1:-$(wofi --dmenu --allow-markup --prompt "Theme (now: ''${cur:-none})" --cache-file /dev/null < ${themes}/list-markup | awk '{print $NF}')}
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
