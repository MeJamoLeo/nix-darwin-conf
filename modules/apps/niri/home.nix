{ config, pkgs, lib, niri, ... }:

let
  # An action with no arguments. niri-flake represents an action as an attrset
  # with a single key (the action name) whose value is its argument list.
  act = name: { action.${name} = [ ]; };

  # An action with arguments. A single argument is implicitly wrapped in a list.
  act' = name: args: { action.${name} = args; };

  # Same key pressed with several modifier prefixes, all running the same action.
  # Used for the arrow/hjkl pairs that niri's default config binds identically.
  forKeys = keys: name: lib.genAttrs keys (_: act name);

  # Workspace 1..9: focus, and move the focused column there.
  workspaceBinds = lib.listToAttrs (
    lib.concatMap
      (n: [
        (lib.nameValuePair "Mod+${toString n}" (act' "focus-workspace" n))
        (lib.nameValuePair "Mod+Ctrl+${toString n}" (act' "move-column-to-workspace" n))
      ])
      (lib.range 1 9)
  );

  # allow-when-locked binds that shell out — the media and brightness keys.
  whenLocked = attrs: lib.mapAttrs (_: v: v // { allow-when-locked = true; }) attrs;
in
{
  # niri-flake の HM モジュール（設定面だけ。programs.niri.enable は nixos.nix 側）。
  imports = [ niri.homeModules.config ];

  # GTK / Qt のアイコンテーマを揃える（DMS = Quickshell/Qt と GTK アプリで同じ
  # アイコンが引けるように。旧 nixos-cp home/gtk.nix）。
  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  # Wayland のクリップボード（tmux / nvim / cp ツールが使う）とランチャ予備。
  home.packages = with pkgs; [ wl-clipboard wofi playerctl ];

  # niri, configured through niri-flake's home-manager module rather than a raw
  # config.kdl. The settings below reproduce niri 26.04's shipped default config
  # exactly, plus the one local divergence (scale 1 on eDP-1).
  #
  # Version note: niri-flake's own niri-stable is 25.08 and its option types are
  # generated from that release's binds.rs, while the compositor here is nixpkgs'
  # niri 26.04. programs.niri.package is therefore pinned to pkgs.niri so the
  # build-time `niri validate` runs against the binary that will actually read
  # this config. Anything 26.04 added after 25.08 cannot be expressed until
  # niri-flake catches up; revisit then.
  programs.niri = {
    package = pkgs.niri;

    settings = {
      input = {
        keyboard.numlock = true;
        touchpad = {
          tap = true;
          natural-scroll = true;
        };
      };

      # The only deliberate divergence from upstream's defaults. The panel is
      # 2160x1350 over 280x170 mm (~196 PPI), so niri's automatic scale picks
      # 1.5; we override to scale 1 on this output, which is the size these
      # eyes are trained on.
      outputs."eDP-1".scale = 1;

      layout = {
        gaps = 16;
        center-focused-column = "never";
        preset-column-widths = [
          { proportion = 0.33333; }
          { proportion = 0.5; }
          { proportion = 0.66667; }
        ];
        default-column-width.proportion = 0.5;

        focus-ring = {
          width = 4;
          active.color = "#7fc8ff";
          inactive.color = "#505050";
        };

        border = {
          enable = false;
          width = 4;
          active.color = "#ffc87f";
          inactive.color = "#505050";
          urgent.color = "#9b0000";
        };

        shadow = {
          softness = 30;
          spread = 5;
          offset = { x = 0; y = 5; };
          color = "#0007";
        };
      };

      # xwayland-satellite runs as an external X server so niri (pure
      # Wayland) can host X11 apps like the VirtualBox Qt5 UI. DMS itself
      # comes up via its own `spawn-at-startup` injected by
      # programs.dank-material-shell.niri.enableSpawn — do not add it
      # here or it would double-spawn.
      spawn-at-startup = [ { argv = [ "xwayland-satellite" ]; } ];

      screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

      window-rules = [
        {
          matches = [ { app-id = "^org\\.wezfurlong\\.wezterm$"; } ];
          default-column-width = { };
        }
        {
          matches = [
            {
              app-id = "firefox$";
              title = "^Picture-in-Picture$";
            }
          ];
          open-floating = true;
        }
      ];

      binds =
        {
          "Mod+Shift+Slash" = act "show-hotkey-overlay";

          # Programs. Launcher, lock and every dms-ipc surface (clipboard,
          # settings, notifications, powermenu, processlist, night mode)
          # are now provided by DMS's home-manager `niri.enableKeybinds`
          # (Mod+Space, Super+Alt+L, Mod+V, Mod+Comma, Mod+N, Mod+X,
          # Mod+M, Mod+Alt+N …). Only the terminal stays niri-side.
          "Mod+T" = (act' "spawn" "kitty") // {
            hotkey-overlay.title = "Open a Terminal: kitty";
          };
          # herdr (tmux-like agent-aware multiplexer) in its own kitty
          # window. Config for herdr itself lives in home/herdr.
          "Mod+Shift+Return" = (act' "spawn" [ "kitty" "herdr" ]) // {
            hotkey-overlay.title = "Launch Herdr";
          };

          "Mod+O" = (act "toggle-overview") // { repeat = false; };
          "Mod+Q" = (act "close-window") // { repeat = false; };

          "Mod+Home" = act "focus-column-first";
          "Mod+End" = act "focus-column-last";
          "Mod+Ctrl+Home" = act "move-column-to-first";
          "Mod+Ctrl+End" = act "move-column-to-last";

          "Mod+BracketLeft" = act "consume-or-expel-window-left";
          "Mod+BracketRight" = act "consume-or-expel-window-right";
          # Mod+Comma is claimed by DMS (settings toggle); consume-window-into-
          # column has no dedicated key now. Use Mod+BracketLeft/Right as the
          # everyday consume/expel; add a rebind if the exact upstream action
          # is missed.
          "Mod+Period" = act "expel-window-from-column";

          "Mod+R" = act "switch-preset-column-width";
          "Mod+Shift+R" = act "switch-preset-column-width-back";
          "Mod+Ctrl+Shift+R" = act "switch-preset-window-height";
          "Mod+Ctrl+R" = act "reset-window-height";

          "Mod+F" = act "maximize-column";
          "Mod+Shift+F" = act "fullscreen-window";
          # Mod+M is claimed by DMS (processlist). maximize-window-to-edges
          # no longer bound.
          "Mod+Ctrl+F" = act "expand-column-to-available-width";
          "Mod+C" = act "center-column";
          "Mod+Ctrl+C" = act "center-visible-columns";

          "Mod+Minus" = act' "set-column-width" "-10%";
          "Mod+Equal" = act' "set-column-width" "+10%";
          "Mod+Shift+Minus" = act' "set-window-height" "-10%";
          "Mod+Shift+Equal" = act' "set-window-height" "+10%";

          # Mod+V is claimed by DMS (clipboard toggle). toggle-window-floating
          # no longer bound; Mod+Shift+V still swaps focus between floating and
          # tiling stacks.
          "Mod+Shift+V" = act "switch-focus-between-floating-and-tiling";
          "Mod+W" = act "toggle-column-tabbed-display";

          "Print" = act "screenshot";
          "Ctrl+Print" = act "screenshot-screen";
          "Alt+Print" = act "screenshot-window";

          "Mod+Escape" = (act "toggle-keyboard-shortcuts-inhibit") // {
            allow-inhibiting = false;
          };

          "Mod+Shift+E" = act "quit";
          "Ctrl+Alt+Delete" = act "quit";
          "Mod+Shift+P" = act "power-off-monitors";
        }

        # Arrow keys and hjkl are bound to the same actions throughout.
        // forKeys [ "Mod+Left" "Mod+H" ] "focus-column-left"
        // forKeys [ "Mod+Down" "Mod+J" ] "focus-window-down"
        // forKeys [ "Mod+Up" "Mod+K" ] "focus-window-up"
        // forKeys [ "Mod+Right" "Mod+L" ] "focus-column-right"

        // forKeys [ "Mod+Ctrl+Left" "Mod+Ctrl+H" ] "move-column-left"
        // forKeys [ "Mod+Ctrl+Down" "Mod+Ctrl+J" ] "move-window-down"
        // forKeys [ "Mod+Ctrl+Up" "Mod+Ctrl+K" ] "move-window-up"
        // forKeys [ "Mod+Ctrl+Right" "Mod+Ctrl+L" ] "move-column-right"

        // forKeys [ "Mod+Shift+Left" "Mod+Shift+H" ] "focus-monitor-left"
        // forKeys [ "Mod+Shift+Down" "Mod+Shift+J" ] "focus-monitor-down"
        // forKeys [ "Mod+Shift+Up" "Mod+Shift+K" ] "focus-monitor-up"
        // forKeys [ "Mod+Shift+Right" "Mod+Shift+L" ] "focus-monitor-right"

        // forKeys [ "Mod+Shift+Ctrl+Left" "Mod+Shift+Ctrl+H" ] "move-column-to-monitor-left"
        // forKeys [ "Mod+Shift+Ctrl+Down" "Mod+Shift+Ctrl+J" ] "move-column-to-monitor-down"
        // forKeys [ "Mod+Shift+Ctrl+Up" "Mod+Shift+Ctrl+K" ] "move-column-to-monitor-up"
        // forKeys [ "Mod+Shift+Ctrl+Right" "Mod+Shift+Ctrl+L" ] "move-column-to-monitor-right"

        // forKeys [ "Mod+Page_Down" "Mod+U" ] "focus-workspace-down"
        // forKeys [ "Mod+Page_Up" "Mod+I" ] "focus-workspace-up"
        // forKeys [ "Mod+Ctrl+Page_Down" "Mod+Ctrl+U" ] "move-column-to-workspace-down"
        // forKeys [ "Mod+Ctrl+Page_Up" "Mod+Ctrl+I" ] "move-column-to-workspace-up"
        // forKeys [ "Mod+Shift+Page_Down" "Mod+Shift+U" ] "move-workspace-down"
        // forKeys [ "Mod+Shift+Page_Up" "Mod+Shift+I" ] "move-workspace-up"

        // workspaceBinds

        # Mouse wheel. Rate-limited so a flick of the wheel does not tear
        # through several workspaces.
        // lib.mapAttrs (_: v: v // { cooldown-ms = 150; }) {
          "Mod+WheelScrollDown" = act "focus-workspace-down";
          "Mod+WheelScrollUp" = act "focus-workspace-up";
          "Mod+Ctrl+WheelScrollDown" = act "move-column-to-workspace-down";
          "Mod+Ctrl+WheelScrollUp" = act "move-column-to-workspace-up";
        }

        // {
          "Mod+WheelScrollRight" = act "focus-column-right";
          "Mod+WheelScrollLeft" = act "focus-column-left";
          "Mod+Ctrl+WheelScrollRight" = act "move-column-right";
          "Mod+Ctrl+WheelScrollLeft" = act "move-column-left";

          # Shift+wheel scrolls horizontally in most applications; mirror that.
          "Mod+Shift+WheelScrollDown" = act "focus-column-right";
          "Mod+Shift+WheelScrollUp" = act "focus-column-left";
          "Mod+Ctrl+Shift+WheelScrollDown" = act "move-column-right";
          "Mod+Ctrl+Shift+WheelScrollUp" = act "move-column-left";
        }

        # Audio sink/source and brightness keys are owned by DMS
        # (dms-ipc audio / brightness, both allow-when-locked). Only the
        # transport keys stay niri-side because DMS doesn't ship an mpris
        # controller.
        // whenLocked {
          "XF86AudioPlay" = act' "spawn-sh" "playerctl play-pause";
          "XF86AudioStop" = act' "spawn-sh" "playerctl stop";
          "XF86AudioPrev" = act' "spawn-sh" "playerctl previous";
          "XF86AudioNext" = act' "spawn-sh" "playerctl next";
        };
    };
  };

  # Mod+T launches kitty (configured in home/kitty.nix). Launcher, bar,
  # notifications and lock screen come from DankMaterialShell
  # (programs.dms-shell in hosts/x1nano/configuration.nix), so no extra
  # user packages are needed here. playerctl / brightnessctl / wpctl,
  # referenced by the media/brightness binds above, are already present
  # elsewhere in the profile.
}
