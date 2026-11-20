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

  # All wallpapers go into one folder under ~/Pictures: the DMS wallpaper tab lists the current
  # wallpaper's folder, and a non-store path stays valid across nixpkgs updates.
  # Collections with unclear licences (e.g. dharmx/walls) are deliberately left out.
  wallpaperSources = with pkgs; {
    pop = pop-wallpapers;
    pophp = pop-hp-wallpapers;
    system76 = system76-wallpapers;
    cosmic = cosmic-wallpapers;
    budgie = budgie-backgrounds;
    gnome = gnome-backgrounds;
    kde = kdePackages.plasma-workspace-wallpapers;
    elementary = pantheon.elementary-wallpapers;
    mate = mate-backgrounds;
    adapta = adapta-backgrounds;
    f32 = fedora-backgrounds.f32;
    f33 = fedora-backgrounds.f33;
    f34 = fedora-backgrounds.f34;
    f35 = fedora-backgrounds.f35;
    f36 = fedora-backgrounds.f36;
    f37 = fedora-backgrounds.f37;
    f38 = fedora-backgrounds.f38;
    terryblacks = runCommand "terry-blacks-share" {} ''
      mkdir -p $out/share/backgrounds
      ln -s ${wallpapers}/day.png $out/share/backgrounds/day.png
      ln -s ${wallpapers}/night.png $out/share/backgrounds/night.png
    '';
  } // import ./extra-wallpapers.nix {inherit pkgs;}
    // lib.mapAttrs' (n: v: lib.nameValuePair "nixos-${n}" v)
    (lib.filterAttrs (_: lib.isDerivation) pkgs.nixos-artwork.wallpapers);
  wallpaperDir = pkgs.runCommand "wallpaper-choices" {
    nativeBuildInputs = [ pkgs.python3 pkgs.libjxl ];
  } ''
    python3 ${./collect-wallpapers.py} $out ${lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "${n}=${v}") wallpaperSources)}
  '';
  wallpaperHome = "${config.home.homeDirectory}/Pictures/Wallpapers";
  defaultWallpaper = "${wallpaperHome}/pop-ahmadreza-sajadi-10140-edit.jpg";
in {
  imports = [ dms.homeModules.dank-material-shell dms.homeModules.niri ];

  home.file."Pictures/Wallpapers".source = wallpaperDir;

  # Do not symlink session.json: DMS also writes runtime state there (night mode etc.). Only the
  # wallpaper key is touched, and only if unset or outside ~/Pictures/Wallpapers (keeps DMS picks).
  # perModeWallpaper is off: the theme is dark-only, so a per-mode picture would apply to one mode.
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
    #
    # enableKeybinds warns when combined with includes.enable (it duplicates dms/binds.kdl), and includes
    # is needed for colours; so the binds are copied into programs.niri.settings.binds below.
    niri = {
      enableSpawn = true;
      enableKeybinds = false;
    };

    settings = {
      # Workspace switcher: show the app icon of each window living in a
      # workspace, not just the workspace index. Closest thing DMS ships
      # to the "spatial map with icons" ask.
      showWorkspaceApps = true;

      popupTransparency = 0.67;

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
        # Bar background fully transparent; widgets keep a faint backing so text stays readable.
        transparency = 0.0;
        widgetTransparency = 0.35;
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

  # Same keys as DMS's enableKeybinds (disabled above), copied from its distro/nix/niri.nix.
  programs.niri.settings.binds = with config.lib.niri.actions; let
    ipc = spawn "dms" "ipc";
    locked = action: {
      allow-when-locked = true;
      inherit action;
    };
  in {
    "Mod+Space" = { action = ipc "spotlight" "toggle"; hotkey-overlay.title = "Toggle Application Launcher"; };
    "Mod+N" = { action = ipc "notifications" "toggle"; hotkey-overlay.title = "Toggle Notification Center"; };
    "Mod+Comma" = { action = ipc "settings" "toggle"; hotkey-overlay.title = "Toggle Settings"; };
    "Mod+P" = { action = ipc "notepad" "toggle"; hotkey-overlay.title = "Toggle Notepad"; };
    "Super+Alt+L" = { action = ipc "lock" "lock"; hotkey-overlay.title = "Toggle Lock Screen"; };
    "Mod+X" = { action = ipc "powermenu" "toggle"; hotkey-overlay.title = "Toggle Power Menu"; };
    "Mod+V" = { action = ipc "clipboard" "toggle"; hotkey-overlay.title = "Toggle Clipboard Manager"; };
    "Mod+M" = { action = ipc "processlist" "toggle"; hotkey-overlay.title = "Toggle Process List"; };
    "Mod+Alt+N" = locked (ipc "night" "toggle") // { hotkey-overlay.title = "Toggle Night Mode"; };
    "XF86AudioRaiseVolume" = locked (ipc "audio" "increment" "3");
    "XF86AudioLowerVolume" = locked (ipc "audio" "decrement" "3");
    "XF86AudioMute" = locked (ipc "audio" "mute");
    "XF86AudioMicMute" = locked (ipc "audio" "micmute");
    "XF86MonBrightnessUp" = locked (ipc "brightness" "increment" "5" "");
    "XF86MonBrightnessDown" = locked (ipc "brightness" "decrement" "5" "");
    "XF86TouchpadToggle" = locked (spawn "niri" "msg" "action" "toggle-touchpad") // { repeat = false; };
  };
}
