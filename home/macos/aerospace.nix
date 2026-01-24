{
  config,
  lib,
  ...
}: let
  homeDir = config.home.homeDirectory;
  bordersBin = "/opt/homebrew/bin/borders";
  layoutLib = "${homeDir}/bin/aerospace-layout-lib.sh";
in {
  # AeroSpace main configuration
  home.file.".aerospace.toml" = {
    force = true;
    text = ''
      start-at-login = true

      # Start helpers with AeroSpace
      after-startup-command = [
        # JankyBorders (borders) for focused window highlight
        "exec-and-forget ${bordersBin} active_color=0xff89b4fa inactive_color=0x00000000 width=10.0",
      ]

      default-root-container-layout = "tiles"
      default-root-container-orientation = "auto"
      enable-normalization-flatten-containers = true
      enable-normalization-opposite-orientation-for-nested-containers = true
      workspace-to-monitor-force-assignment = { "1" = 1, "2" = 2 , "3" = 3}

      on-window-detected = [
        { if.app-id = "com.spotify.client", run = "move-node-to-workspace s" }, # Spotify
        { if.app-id = "com.hnc.Discord", run = "move-node-to-workspace d" }, # Discord
        { if.app-id = "md.obsidian", run = "move-node-to-workspace o" }, # Obsidian
        { if.app-id = "com.todesktop.230313mzl4w4u92", run = "move-node-to-workspace e" }, # Cursor
        { if.app-id = "com.macpomodoro", run = "move-node-to-workspace f" }, # Focus To-Do (WebPomodoro)
        { if.app-id = "com.openai.chat", run = "move-node-to-workspace c" }, # ChatGPT
        { if.app-id = "com.brave.Browser", run = "move-node-to-workspace b" }, # Brave
        { if.app-id = "com.apple.Preview", run = "move-node-to-workspace i" }, # Preview
        { if.app-id = "com.github.wez.wezterm", run = "move-node-to-workspace w" }, # WezTerm
      ]

      [gaps]
      inner.horizontal = 10
      inner.vertical = 10
      outer.left = 12
      outer.bottom = 12
      outer.top = 12
      outer.right = 12

      [mode.main.binding]
      alt-tab = "focus-monitor --wrap-around next"
      alt-shift-tab = "move-node-to-monitor --wrap-around --focus-follows-window next"
      alt-h = "focus left"
      alt-j = "focus down"
      alt-k = "focus up"
      alt-l = "focus right"
      alt-q = "close"


      alt-1 = "workspace 1"
      alt-2 = "workspace 2"
      alt-3 = "workspace 3"
      alt-4 = "workspace 4"
      alt-5 = "workspace 5"
      alt-6 = "workspace 6"
      alt-7 = "workspace 7"
      alt-8 = "workspace 8"
      alt-9 = "workspace 9"
      alt-a = "workspace a"
      alt-b = "workspace b"
      alt-c = "workspace c"
      alt-d = "workspace d"
      alt-e = "workspace e"
      alt-f = "workspace f"
      alt-g = "workspace g"
      alt-i = "workspace i"
      alt-m = "workspace m"
      alt-n = "workspace n"
      alt-o = "workspace o"
      alt-p = "workspace p"
      alt-r = "workspace r"
      alt-s = "workspace s"
      alt-t = "workspace t"
      alt-u = "workspace u"
      alt-v = "workspace v"
      alt-w = "workspace w"
      alt-x = "workspace x"
      alt-y = "workspace y"
      alt-z = "workspace z"


      cmd-alt-ctrl-shift-p = "exec-and-forget ${homeDir}/bin/layout-box-atcoder.sh"
      cmd-alt-ctrl-shift-b = "exec-and-forget ${homeDir}/bin/layout-brave-sub.sh"


      alt-shift-h = "move left"
      alt-shift-j = "move down"
      alt-shift-k = "move up"
      alt-shift-l = "move right"


      alt-shift-1 = "move-node-to-workspace 1"
      alt-shift-2 = "move-node-to-workspace 2"
      alt-shift-3 = "move-node-to-workspace 3"
      alt-shift-4 = "move-node-to-workspace 4"
      alt-shift-5 = "move-node-to-workspace 5"
      alt-shift-6 = "move-node-to-workspace 6"
      alt-shift-7 = "move-node-to-workspace 7"
      alt-shift-8 = "move-node-to-workspace 8"
      alt-shift-9 = "move-node-to-workspace 9"
      alt-shift-a = "move-node-to-workspace a"
      alt-shift-b = "move-node-to-workspace b"
      alt-shift-c = "move-node-to-workspace c"
      alt-shift-d = "move-node-to-workspace d"
      alt-shift-e = "move-node-to-workspace e"
      alt-shift-f = "move-node-to-workspace f"
      alt-shift-g = "move-node-to-workspace g"
      alt-shift-i = "move-node-to-workspace i"
      alt-shift-m = "move-node-to-workspace m"
      alt-shift-n = "move-node-to-workspace n"
      alt-shift-o = "move-node-to-workspace o"
      alt-shift-p = "move-node-to-workspace p"
      alt-shift-r = "move-node-to-workspace r"
      alt-shift-s = "move-node-to-workspace s"
      alt-shift-t = "move-node-to-workspace t"
      alt-shift-u = "move-node-to-workspace u"
      alt-shift-v = "move-node-to-workspace v"
      alt-shift-w = "move-node-to-workspace w"
      alt-shift-x = "move-node-to-workspace x"
      alt-shift-y = "move-node-to-workspace y"
      alt-shift-z = "move-node-to-workspace z"

      cmd-alt-ctrl-shift-h = "resize width -50"
      cmd-alt-ctrl-shift-j = "resize height -50"
      cmd-alt-ctrl-shift-k = "resize height +50"
      cmd-alt-ctrl-shift-l = "resize width +50"

      cmd-alt-ctrl-shift-1 = "move-workspace-to-monitor 1"
      cmd-alt-ctrl-shift-2 = "move-workspace-to-monitor 2"
      cmd-alt-ctrl-shift-3 = "move-workspace-to-monitor 3"

      [mode.resize.binding]
      alt-r = "mode main"
      alt-h = "resize smart -50"
      alt-l = "resize smart +50"
    '';
  };

  home.file."bin/layout-box-atcoder.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      source "${layoutLib}"

      workspace="p"
      sheet_url="https://docs.google.com/spreadsheets/d/1p4rGvtYcqk9hfsl8PSeMlsNqFu34o8DOGM78MBn7dg4/edit"
      gemini_url="https://gemini.google.com/app"
      pause="0.5"

      ensure_aerospace || exit 1

      log_step "Switch to workspace $workspace and reset layout"
      ensure_workspace "$workspace"
      run_layout flatten-workspace-tree

      log_step "Launch Comet (Sheets)"
      open_app "Comet" --new-window "$sheet_url"
      sleep "$pause"

      log_step "Launch Comet (AtCoder)"
      open_app "Comet" --new-window "$gemini_url"
      sleep "$pause"

      log_step "Arrange left stack (vertical)"
      run_layout focus left
      run_layout layout v_tiles
      run_layout move up
      run_layout move down
      run_layout balance-sizes

      log_step "Launch WezTerm (~/Box) and move to right"
      open_wezterm "$HOME/Box"
      sleep "$pause"
      run_layout layout h_tiles
      run_layout focus right
      run_layout balance-sizes

      log_step "--- hyper+P layout done ---"
    '';
  };

  home.file."bin/layout-brave-sub.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      source "${layoutLib}"

      LOG_FILE="$HOME/Library/Logs/layout-brave-sub.log"
      mkdir -p "$(dirname "$LOG_FILE")"
      exec > >(tee -a "$LOG_FILE") 2>&1
      log_step "--- hyper+B Brave sub profile start ---"

      workspace="b"
      url_reins="https://system.reins.jp/main/BK/GBK003100"
      url_bk="https://bk-m01.bukken1.com/estates/"
      profile="Profile 1" # Brave profile name for 'sub'

      ensure_aerospace || exit 1

      ensure_workspace "$workspace"
      open_app "Brave Browser" --profile-directory="$profile" --new-window "$url_reins"
      open_app "Brave Browser" --profile-directory="$profile" --new-window "$url_bk"

      log_step "--- hyper+B Brave sub profile done ---"
    '';
  };

  home.file."bin/aerospace-layout-lib.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
      aerospace_bin="/opt/homebrew/bin/aerospace"

      log_step() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
      }

      ensure_aerospace() {
        if ! command -v "$aerospace_bin" >/dev/null 2>&1; then
          log_step "aerospace CLI not found at $aerospace_bin"
          return 1
        fi
        return 0
      }

      run_layout() {
        "$aerospace_bin" "$@" 2>/dev/null || true
      }

      ensure_workspace() {
        "$aerospace_bin" workspace "$1" 2>/dev/null || true
      }

      open_app() {
        local app="$1"
        shift
        /usr/bin/open -n -a "$app" --args "$@"
      }

      open_wezterm() {
        local cwd="$1"
        if command -v wezterm >/dev/null 2>&1; then
          wezterm cli spawn --cwd "$cwd" >/dev/null 2>&1 || true
        fi
        /usr/bin/open -n -a "WezTerm" --args start --cwd "$cwd"
      }
    '';
  };

  # Restart AeroSpace on activation so hotkeys pick up new config
  home.activation.aerospaceAutoStart = lib.hm.dag.entryAfter ["writeBoundary"] ''
    /usr/bin/pkill -x "AeroSpace" 2>/dev/null || true
    sleep 0.5
    /usr/bin/open -n -a "AeroSpace"
  '';
}
