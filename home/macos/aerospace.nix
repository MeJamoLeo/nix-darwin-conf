{config, lib, ...}: let
  homeDir = config.home.homeDirectory;
  bordersBin = "/opt/homebrew/bin/borders";
  aerospaceBin = "/opt/homebrew/bin/aerospace";
  layoutScript = "${homeDir}/bin/layout-box-atcoder.sh";
in {
  # AeroSpace main configuration
  home.file.".aerospace.toml" = {
    force = true;
    text = ''
    start-at-login = true

    # Start helpers with AeroSpace
    after-startup-command = [
      # JankyBorders (borders) for focused window highlight
      "exec-and-forget ${bordersBin} active_color=0xff89b4fa inactive_color=0x00000000 width=6.0",
    ]

    default-root-container-layout = "tiles"
    default-root-container-orientation = "auto"
    enable-normalization-flatten-containers = true
    enable-normalization-opposite-orientation-for-nested-containers = true

    on-window-detected = [
      { if.app-id = "com.spotify.client", run = "move-node-to-workspace s" },
      { if.app-id = "com.hnc.Discord", run = "move-node-to-workspace d" },
      { if.app-id = "ai.perplexity.comet", run = "move-node-to-workspace b" },
      { if.app-id = "md.obsidian", run = "move-node-to-workspace o" },
      { if.app-id = "com.todesktop.230313mzl4w4u92", run = "move-node-to-workspace e" },
    ]

    [gaps]
    inner.horizontal = 6
    inner.vertical = 6
    outer.left = 8
    outer.bottom = 8
    outer.top = 8
    outer.right = 8

    [mode.main.binding]
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
    cmd-alt-ctrl-shift-p = "exec-and-forget ${layoutScript}"
    alt-shift-h = "move left"
    alt-shift-j = "move down"
    alt-shift-k = "move up"
    alt-shift-l = "move right"
    alt-shift-1 = "move-node-to-workspace 1"
    alt-shift-2 = "move-node-to-workspace 2"
    alt-shift-3 = "move-node-to-workspace 3"
    alt-shift-4 = "move-node-to-workspace 4"
    alt-shift-5 = "move-node-to-workspace 5"
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
  '';
  };

  home.file."bin/layout-box-atcoder.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      LOG_FILE="$HOME/Library/Logs/layout-box-atcoder.log"
      mkdir -p "$(dirname "$LOG_FILE")"
      exec > >(tee -a "$LOG_FILE") 2>&1
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- hyper+P layout start ---"

      PATH="/opt/homebrew/bin:$PATH"
      aerospace="${aerospaceBin}"
      workspace="p"
      sheet_url="https://docs.google.com/spreadsheets/"
      atcoder_url="https://atcoder.jp/"

      if ! command -v "$aerospace" >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] aerospace CLI not found at $aerospace" >&2
        exit 1
      fi

      # Move to workspace p and reset layout
      "$aerospace" workspace "$workspace"
      "$aerospace" flatten-workspace-tree
      "$aerospace" layout h_tiles

      # Left: Comet (Sheets)
      open -na "Comet" --args "$sheet_url"
      sleep 0.3

      # Right: WezTerm in ~/Box
      open -na "WezTerm" --args start --cwd "$HOME/Box"
      sleep 0.3

      # Left container -> vertical split, then second Comet (AtCoder)
      "$aerospace" focus left
      "$aerospace" layout v_tiles
      open -na "Comet" --args "$atcoder_url"
      sleep 0.3

      "$aerospace" balance-sizes
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- hyper+P layout done ---"
    '';
  };

  # Restart AeroSpace on activation so hotkeys pick up new config
  home.activation.aerospaceAutoStart = lib.hm.dag.entryAfter ["writeBoundary"] ''
    /usr/bin/pkill -x "AeroSpace" 2>/dev/null || true
    sleep 0.5
    /usr/bin/open -n -a "AeroSpace"
  '';
}
