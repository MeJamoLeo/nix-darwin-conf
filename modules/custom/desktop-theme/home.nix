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
#  一覧は kitty-themes＋iTerm2-Color-Schemes から人気のダーク系 58 個（fzf、↑↓ で即反映）。選ぶと
#    - DMS（バー・ランチャー・コントロールセンター）と niri の枠色（DMS が書き出す）
#    - Ghostty（開いている端末も SIGUSR2 で読み直させて即反映）
#  が切り替わる。配色の元は kitty 形式のテーマ集（端末は 2026-11-20 に kitty から Ghostty へ
#  移したが、テーマ集はそのまま使う）。DMS 用は ./gen-dms-theme.py、Ghostty 用は
#  ./gen-ghostty-theme.py で自動で作る。
#  ayu Dark だけは手で合わせた ./ayu-dark.dms.json を使う（2026-11-19 に作った物）。
#
#  選んだ配色は ~/.local/state/desktop-theme/ に置く（name / dms.json / ghostty.conf）。
#  DMS の customThemeFile と Ghostty の config-file がここを指す。switch では選択を上書きせず、
#  中身だけ今の store の版へ書き直す（未選択・候補から消えた物なら ayu に戻す）。
#  dms.json は store への symlink にせず、実ファイルを mv で置き換える（下の apply）。
#
#  画面に出る文字列（fzf の案内・niri の hotkey 表示）は英語にする（2026-11-20 本人の希望）。
#
#  nvim とブラウザは追従しない（テーマごとのプラグイン対応が要るので別段）。
#
##########################################################################
let
  kittyThemes = "${pkgs.kitty-themes}/share/kitty-themes/themes";
  # kitty-themes に無い物（Iceberg など）。名前 → conf のパス。
  extraThemes = import ./extra-themes.nix {inherit pkgs;};
  confOf = n: extraThemes.${n} or "${kittyThemes}/${n}.conf";

  # 表示名 = kitty-themes のファイル名（.conf 抜き）。並びがそのまま一覧の順。
  # 2026-11-20: ダーク系だけ 58 個（kitty-themes に無い物も足す。明るい物は外した。端末を 50% 透かしているので読みにくい）。
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
    # ここから 8 個は Iceberg と色の傾きが近い物（extra-themes.nix から。Kanagawabones は kitty-themes にもある）
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

  # 選んだ名前のファイルを state へ書く。一時ファイルに書いてから mv で置き換える
  # （2026-11-20：`cat >` だといったん空になった瞬間を DMS が読み「Invalid JSON format」の
  # トーストが出た。mv の置き換えでも DMS は追従することを実機で確認済み）。
  apply = ''
    mkdir -p "${stateDir}"
    for f in dms.json ghostty.conf; do
      cp "${themes}/$name/$f" "${stateDir}/.$f.tmp"
      chmod 644 "${stateDir}/.$f.tmp"
      mv -f "${stateDir}/.$f.tmp" "${stateDir}/$f"
    done
    printf '%s\n' "$name" > "${stateDir}/name"
  '';

  # theme-switch NAME … その配色にする（DMS・Ghostty）。
  # theme-switch       … 端末の中で fzf の一覧を出す。↑↓ でフォーカスが動くたびに即反映し、
  #                       Enter で決定、Esc で開いたときの配色に戻す。右側は fastfetch
  #                       （OS の情報と 16 色のパレット。端末の色なので配色と一緒に変わる）。
  themeSwitch = pkgs.writeShellApplication {
    name = "theme-switch";
    runtimeInputs = with pkgs; [fzf fastfetch procps coreutils gnugrep];
    text = ''
      if [ $# -gt 0 ]; then
        name=$1
        [ -d "${themes}/$name" ] || { echo "unknown theme: $name" >&2; exit 1; }
        ${apply}
        # 開いている Ghostty に設定を読み直させる（SIGUSR2。常駐サービスの ReloadSignal と同じ）。
        # プロセス名は .ghostty-wrapped が 15 文字で切れた物。
        pkill -USR2 -x '.ghostty-wrappe' || true
        exit 0
      fi

      # 開いた直後の focus（先頭行）で配色が変わらないよう、読み込みが終わって今の配色の
      # 行へ移るまでは focus を外しておく（2026-11-20：start:pos だけでは先頭の ayu が当たった）。
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

  # ? を付けると、ファイルが無くてもエラーにしない（初回の switch 前など）。
  programs.ghostty.settings.config-file = "?${stateDir}/ghostty.conf";

  # 一覧は専用の Ghostty を浮かせて開く（下の window-rules）。theme-switch は store の絶対パスで
  # 呼ぶ（PATH の /etc/profiles は nixos-rebuild でしか更新されないので、home-manager だけ
  # 当てた状態でも動くように）。
  programs.niri.settings.binds."Mod+Shift+T" = {
    # 常駐の Ghostty に窓を開かせる（+new-window。別プロセスで起こすと 1.9 秒かかる）。
    # 同じアプリ ID になるので、浮かせる規則はタイトルで当てる。
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
