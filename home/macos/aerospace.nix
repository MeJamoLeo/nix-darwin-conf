{...}: let
  bordersBin = "/opt/homebrew/bin/borders";
in {
  # AeroSpace main configuration
  home.file.".aerospace.toml" = {
    force = true;
    text = ''
      start-at-login = true

      # Start helpers with AeroSpace
      after-startup-command = [
        # JankyBorders (borders) for focused window highlight
        "exec-and-forget ${bordersBin} active_color=0xff6d28d9 inactive_color=0x00000000 width=20.0",
      ]

      on-focus-changed = ["move-mouse window-lazy-center"]

      default-root-container-layout = "tiles"
      default-root-container-orientation = "auto"
      enable-normalization-flatten-containers = false
      enable-normalization-opposite-orientation-for-nested-containers = false
      on-window-detected = [
        { if.app-id = "com.spotify.client", run = "move-node-to-workspace w" }, # Spotify
        { if.app-id = "com.hnc.Discord", run = "move-node-to-workspace q" }, # Discord
        { if.app-id = "jp.naver.line.mac", run = "move-node-to-workspace q" }, # LINE
        { if.app-id = "net.whatsapp.WhatsApp", run = "move-node-to-workspace q" }, # WhatsApp
        { if.app-id = "com.tinyspeck.slackmacgap", run = "move-node-to-workspace q" }, # Slack
        # Catch-all: routing 未設定アプリは起動時だけ f に集約
        { if.during-aerospace-startup = true, run = "move-node-to-workspace f" },
      ]

      [workspace-to-monitor-force-assignment]
      q = "secondary"
      w = "secondary"
      e = "secondary"
      r = "secondary"
      v = [3, "main"]
      c = [3, "main"]
      x = [3, "main"]
      z = [3, "main"]

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
      alt-enter = "fullscreen"

      # Workspaces (column-grouped: main / secondary / tertiary per finger)
      # Index finger (most frequent)
      alt-f = "workspace f"
      alt-r = "workspace r"
      alt-v = "workspace v"
      # Middle finger
      alt-d = "workspace d"
      alt-e = "workspace e"
      alt-c = "workspace c"
      # Ring finger
      alt-s = "workspace s"
      alt-w = "workspace w"
      alt-x = "workspace x"
      # Pinky (least frequent)
      alt-a = "workspace a"
      alt-q = "workspace q"
      alt-z = "workspace z"

      alt-comma = "resize smart -50"
      alt-period = "resize smart +50"

      # Right Top Row, Layout switching
      alt-y = "flatten-workspace-tree"
      alt-u = "layout h_accordion h_tiles"
      alt-i = "layout h_tiles"
      alt-o = "layout v_tiles"
      alt-p = "layout floating tiling"
      alt-semicolon = "reload-config"
      alt-m = "mode join"

      # Right Home Position Row, jkl;
      alt-shift-h = "move left"
      alt-shift-j = "move down"
      alt-shift-k = "move up"
      alt-shift-l = "move right"

      # Move node to workspace (same column-grouped order)
      # Index finger
      alt-shift-f = "move-node-to-workspace f"
      alt-shift-r = "move-node-to-workspace r"
      alt-shift-v = "move-node-to-workspace v"
      # Middle finger
      alt-shift-d = "move-node-to-workspace d"
      alt-shift-e = "move-node-to-workspace e"
      alt-shift-c = "move-node-to-workspace c"
      # Ring finger
      alt-shift-s = "move-node-to-workspace s"
      alt-shift-w = "move-node-to-workspace w"
      alt-shift-x = "move-node-to-workspace x"
      # Pinky
      alt-shift-a = "move-node-to-workspace a"
      alt-shift-q = "move-node-to-workspace q"
      alt-shift-z = "move-node-to-workspace z"

      [mode.join.binding]
      h = ["join-with left", "mode main"]
      j = ["join-with down", "mode main"]
      k = ["join-with up", "mode main"]
      l = ["join-with right", "mode main"]
      esc = "mode main"

    '';
  };
}
