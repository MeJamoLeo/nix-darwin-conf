{ config, pkgs, lib, dms, ... }:

# DankMaterialShell: full Quickshell-based desktop shell (bar, launcher,
# notifications, lock screen, control center). Driven through the DMS
# upstream flake's home-manager module rather than nixpkgs' NixOS module,
# because only the flake surface exposes `settings` for declarative
# widget layout and theming.
#
# Do NOT run `dms setup` — that script is for non-Nix distros and tries
# to write ~/.config/niri/config.kdl directly, which fails because
# home-manager owns that path as a store symlink. Instead this module's
# `niri.includes` (default: true) renames niri-flake's output to
# ~/.config/niri/hm.kdl and generates a wrapper config.kdl that
# `include`s hm.kdl plus DMS's runtime files (dms/*.kdl). DMS drops
# colors/outputs/binds into ~/.config/niri/dms/ at runtime; niri reloads
# and picks them up. Static config stays in Nix; only dynamic surfaces
# are runtime-mutable.
#
# Extending: `settings` mirrors the schema in
# github:AvengeMedia/DankMaterialShell/src/SettingsSpec.js. To grow this
# module: touch the setting in the DMS control center, copy the resulting
# ~/.config/DankMaterialShell/settings.json snippet, translate it into
# Nix, and add it below. That flow keeps everything reproducible while
# skipping the need to invent the JSON from scratch.

let
  # 壁紙：Terry Black's（オースティンの BBQ 屋）を描いた手描き風イラストを、light 用（昼）と
  # dark 用（夜・ネオン）の2枚にしたもの。2026-10-24 に Claude が本物の写真と T シャツを参考に描いた
  # （写しではない）。絵は ./wallpaper/gen.py が SVG を吐き、ここで x1nano の画面サイズ
  # （2160x1350）の PNG にする。フォントは nixpkgs から固定するので機体で見た目が変わらない。
  # 絵を変えたいときは gen.py を直して switch するだけ（2枚とも同じ構図から出る）。
  wallpapers =
    pkgs.runCommand "wallpaper-terry-blacks" {
      nativeBuildInputs = [pkgs.librsvg pkgs.python3];
      FONTCONFIG_FILE = pkgs.makeFontsConf {
        fontDirectories = [pkgs.dancing-script pkgs.dejavu_fonts];
      };
    } ''
      export HOME=$TMPDIR
      mkdir -p $out
      for m in day night; do
        python3 ${./wallpaper/gen.py} $m $TMPDIR/$m.svg
        rsvg-convert -w 2160 -h 1350 $TMPDIR/$m.svg -o $out/$m.png
      done
    '';

  # 2026-11-20: 壁紙の選択肢＝pop-os/wallpapers（nixpkgs の pop-wallpapers、CC-BY-SA-4.0 /
  # public domain）の 38 枚＋Terry Black's の昼夜 2 枚。1 つのフォルダ ~/Pictures/Wallpapers に
  # symlink で並べる。DMS のダッシュボードの壁紙タブは「今の壁紙があるフォルダ」を一覧するので、
  # 全部が同じフォルダにあれば、そこから選べる。パスが store ではなく ~/Pictures 起点なので、
  # nixpkgs の更新で store パスが変わっても選んだ壁紙が切れない。
  wallpaperDir = pkgs.runCommand "wallpaper-choices" {} ''
    mkdir -p $out
    ln -s ${pkgs.pop-wallpapers}/share/backgrounds/pop/* $out/
    ln -s ${wallpapers}/day.png $out/terry-blacks-day.png
    ln -s ${wallpapers}/night.png $out/terry-blacks-night.png
  '';
  wallpaperHome = "${config.home.homeDirectory}/Pictures/Wallpapers";
  # 既定は星の軌跡（ayu Dark と 50% 透過の端末に合う暗く静かな絵）。
  defaultWallpaper = "${wallpaperHome}/ahmadreza-sajadi-10140-edit.jpg";
in {
  imports = [ dms.homeModules.dank-material-shell dms.homeModules.niri ];

  home.file."Pictures/Wallpapers".source = wallpaperDir;

  # DMS は壁紙を ~/.local/state/dms/session.json に持つ。このファイルには夜間モード等の
  # 実行時状態も DMS 自身が書くので、丸ごと store symlink にすると壊れる。switch 時に
  # 壁紙のキーだけ触る（rbw・zen と同じ「必要なキーだけ宣言」方式）。
  #
  # 2026-11-20: DMS で選んだ壁紙を switch で上書きしないように変えた。既定へ戻すのは
  # 「未設定」「ファイルが無い」「~/Pictures/Wallpapers の外（旧 store パス等）」のときだけ。
  # perModeWallpaper は切る（配色が dark 固定なので昼夜で絵を替える意味が無く、オンだと
  # 選んだ絵が片方のモードにしか効かない）。
  home.activation.dmsWallpaper = lib.hm.dag.entryAfter ["writeBoundary" "linkGeneration"] ''
    f="${config.xdg.stateHome}/dms/session.json"
    mkdir -p "$(dirname "$f")"
    [ -s "$f" ] || echo '{}' > "$f"
    cur=$(${pkgs.jq}/bin/jq -r '.wallpaperPath // ""' "$f")
    case "$cur" in
      "${wallpaperHome}"/*) [ -e "$cur" ] || cur="" ;;
      *) cur="" ;;
    esac
    w=''${cur:-${defaultWallpaper}}
    tmp=$(mktemp)
    ${pkgs.jq}/bin/jq --arg w "$w" \
      '.perModeWallpaper = false | .wallpaperPath = $w
       | .wallpaperPathLight = $w | .wallpaperPathDark = $w' \
      "$f" > "$tmp" && mv "$tmp" "$f"
  '';

  programs.dank-material-shell = {
    enable = true;
    # バーのカレンダー予定（khal 経由）は使わない。予定の正本は Google カレンダーで、
    # かつ nixos-unstable の khal 0.14.1 は man 出力が作れずビルドが落ちる（2026-10-23）。
    enableCalendarEvents = false;

    # Use the flake-built binary (see extraSpecialArgs comment in flake.nix
    # for the Go-version rationale). Overriding the package skips home-
    # manager's own buildGoModule pass entirely.
    package = dms.packages.${pkgs.stdenv.hostPlatform.system}.dms-shell;

    # niri integration: spawn the DMS shell process from niri, and inject
    # DMS's keybinds directly into programs.niri.settings.binds. The
    # include mechanism's dms/binds.kdl comes up empty at runtime (DMS
    # only fills it via `dms setup`, which we can't run under nix), so
    # keybinds have to come from Nix or launcher/notifications/lock don't
    # work at all.
    niri = {
      enableSpawn = true;
      enableKeybinds = true;
    };

    settings = {
      # Workspace switcher: show the app icon of each window living in a
      # workspace, not just the workspace index. Closest thing DMS ships
      # to the "spatial map with icons" ask.
      showWorkspaceApps = true;

      # ポップアップ（コントロールセンター・ランチャー等）も同じ透け具合に揃える（niri-dots）。
      popupTransparency = 0.67;

      # 配色は ayu Dark（2026-11-19）。DMS の自作テーマ形式（Theme.qml の resolveCustomTheme）で
      # ./ayu-dark.json に書いた。色は ayu-theme/ayu-colors（MIT）の themes/dark.yaml から：
      # 地 surface.base #0D1017・パネル #141821・ポップアップ #0F131A・差し色 accent #E6B450・
      # 青 #59C2FF・灰 #5A6673・エラー #D95757。文字色 #BFBDB6 と副文字 #8A9199 は ayu の
      # 半透明指定（fg に alpha）を地の上で潰した近似値。dark しか書いていないので、ライト
      # モードでも同じ色になる（壁紙の昼夜切替はそのまま動く）。niri の枠色も DMS が
      # この配色から dms/colors.kdl に書き出す。
      currentThemeName = "custom";
      customThemeFile = "${./ayu-dark.json}";

      # DankBar layout. `barConfigs` is a list; DMS overrides the whole
      # entry when settings.json defines it, so this mirrors the upstream
      # default (SettingsSpec.js `barConfigs.def`) with `runningApps`
      # inserted after workspaceSwitcher — everything else matches DMS's
      # own baseline so future upstream additions surface via a rebuild
      # and re-copy from SettingsSpec.js.
      barConfigs = [{
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        # runningApps and focusedWindow removed — workspaceSwitcher already
        # shows per-workspace app icons, so a separate running-apps strip
        # plus focused-window title was redundant clutter.
        leftWidgets = [ "launcherButton" "workspaceSwitcher" ];
        centerWidgets = [ "music" "clock" "weather" ];
        rightWidgets = [ "systemTray" "clipboard" "cpuUsage" "memUsage" "notificationButton" "battery" "controlCenterButton" ];
        spacing = 4;
        innerPadding = 4;
        barLengthPadding = 0;
        bottomGap = 0;
        attachToScreenEdge = false;
        # 2026-11-19: niri-dots に倣ってバーを半透明に（壁紙が透けて画面が軽く見える）。
        transparency = 0.67;
        widgetTransparency = 0.67;
        squareCorners = false;
        noBackground = false;
        maximizeWidgetIcons = false;
        maximizeWidgetText = false;
        removeWidgetPadding = false;
        widgetPadding = 8;
        batteryColorMode = "theme";
        gothCornersEnabled = false;
        gothCornerRadiusOverride = false;
        gothCornerRadiusValue = 12;
        borderEnabled = false;
        borderColor = "surfaceText";
        borderOpacity = 1.0;
        borderThickness = 1;
        widgetOutlineEnabled = false;
        widgetOutlineColor = "primary";
        widgetOutlineOpacity = 1.0;
        widgetOutlineThickness = 1;
        fontScale = 1.0;
        iconScale = 1.0;
        autoHide = false;
        autoHideStrict = false;
        autoHideDelay = 250;
        showOnWindowsOpen = false;
        openOnOverview = false;
        visible = true;
        popupGapsAuto = true;
        popupGapsManual = 4;
        maximizeDetection = true;
        useOverlayLayer = false;
        scrollEnabled = true;
        scrollXBehavior = "column";
        scrollYBehavior = "workspace";
        shadowIntensity = 0;
        shadowOpacity = 60;
        shadowColorMode = "default";
        shadowCustomColor = "#000000";
        clickThrough = false;
        hoverPopouts = false;
        hoverPopoutDelay = 150;
      }];
    };
  };
}
