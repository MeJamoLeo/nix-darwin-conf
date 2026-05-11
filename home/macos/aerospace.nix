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
        { if.app-id = "com.spotify.client", run = "move-node-to-workspace p" }, # Spotify
        { if.app-id = "com.hnc.Discord", run = "move-node-to-workspace p" }, # Discord
        { if.app-id = "md.obsidian", run = "move-node-to-workspace o" }, # Obsidian
        { if.app-id = "com.todesktop.230313mzl4w4u92", run = "move-node-to-workspace e" }, # Cursor
        { if.app-id = "com.openai.chat", run = "move-node-to-workspace c" }, # ChatGPT
        { if.app-id = "com.brave.Browser", run = "move-node-to-workspace b" }, # Brave
        { if.app-id = "jp.naver.line.mac", run = "move-node-to-workspace p" }, # LINE
        { if.app-id = "net.whatsapp.WhatsApp", run = "move-node-to-workspace p" }, # WhatsApp
        { if.app-id = "com.tinyspeck.slackmacgap", run = "move-node-to-workspace p" }, # Slack
      ]

      [workspace-to-monitor-force-assignment]
      i = "secondary"
      o = "secondary"
      p = "secondary"
      u = "secondary"

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
      alt-enter = "fullscreen"

      # Layout switching
      alt-minus = "layout v_tiles"
      alt-equal = "layout h_tiles"
      alt-8 = "layout h_accordion h_tiles"

      alt-1 = "workspace 1"
      alt-2 = "workspace 2"
      alt-3 = "workspace 3"
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
      alt-comma = "resize smart -50"
      alt-period = "resize smart +50"
      alt-r = "mode resize"
      alt-s = "workspace s"
      alt-t = "workspace t"
      alt-u = "workspace u"
      alt-v = "workspace v"
      alt-w = "workspace w"
      alt-y = "workspace y"
      alt-z = "workspace z"

      alt-6 = "flatten-workspace-tree"
      alt-9 = "layout floating tiling"
      alt-0 = "mode join"

      alt-shift-h = "move left"
      alt-shift-j = "move down"
      alt-shift-k = "move up"
      alt-shift-l = "move right"

      alt-shift-1 = "move-workspace-to-monitor 1"
      alt-shift-2 = "move-workspace-to-monitor 2"
      alt-shift-3 = "move-workspace-to-monitor 3"
      alt-shift-a = "move-node-to-workspace a"
      alt-shift-b = "move-node-to-workspace b"
      alt-shift-c = "move-node-to-workspace c"
      alt-shift-d = "move-node-to-workspace d"
      alt-shift-e = "move-node-to-workspace e"
      alt-shift-f = "move-node-to-workspace f"
      alt-shift-g = "move-node-to-workspace g"
      alt-shift-i = "move-node-to-workspace i"
      alt-shift-m = "move-node-to-workspace m"
      alt-shift-o = "move-node-to-workspace o"
      alt-shift-p = "move-node-to-workspace p"
      alt-shift-s = "move-node-to-workspace s"
      alt-shift-t = "move-node-to-workspace t"
      alt-shift-u = "move-node-to-workspace u"
      alt-shift-v = "move-node-to-workspace v"
      alt-shift-w = "move-node-to-workspace w"
      alt-shift-y = "move-node-to-workspace y"
      alt-shift-z = "move-node-to-workspace z"

      [mode.join.binding]
      h = ["join-with left", "mode main"]
      j = ["join-with down", "mode main"]
      k = ["join-with up", "mode main"]
      l = ["join-with right", "mode main"]
      esc = "mode main"

      [mode.resize.binding]
      alt-r = "mode main"
      alt-h = "resize smart -50"
      alt-l = "resize smart +50"
    '';
  };
}
