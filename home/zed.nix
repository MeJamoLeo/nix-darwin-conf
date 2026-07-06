{...}: {
  # Zed は ~/.config/zed/settings.json を読む(JSONC 可だが toJSON の厳密 JSON で問題ない)。
  # 本体は nixpkgs の zed-editor (home/core.nix)。設定変更は UI からではなく
  # ここを編集して rebuild する(store への read-only symlink になるため、
  # UI のテーマピッカー等から保存しようとするとエラーになる)。
  # デフォルト一覧: コマンドパレット `zed: open default settings`
  # prompts/ と themes/ は実行時データなので管理しない。
  xdg.configFile."zed/settings.json" = {
    force = true; # 手動運用時代の settings.json が残っていても上書きする
    text = builtins.toJSON {
      # nix 管理では app bundle が read-only で self-update は成立しない。
      # 更新は flake update 経由であることを明示しておく。
      auto_update = false;

      vim_mode = true;
      session.trust_all_worktrees = true;

      # Claude Code を ACP 経由のエージェントとして使う
      agent_servers.claude-acp.type = "registry";

      icon_theme = "Zed (Default)";
      ui_font_size = 16;
      buffer_font_size = 15;
      theme = {
        mode = "dark";
        light = "Ayu Light";
        dark = "One Dark";
      };
    };
  };
}
