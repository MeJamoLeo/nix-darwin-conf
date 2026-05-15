{...}: {
  # cmux reads ~/.config/cmux/cmux.json. Settings written here become
  # file-managed; anything omitted falls back to in-app Settings.
  # Schema: https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json
  xdg.configFile."cmux/cmux.json" = {
    force = true; # cmuxが起動時に同名ファイルを生成するので上書き許可
    text = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
    schemaVersion = 1;
    # 設定を増やしたくなったらここに足す。例:
    # app = { sendAnonymousTelemetry = false; warnBeforeQuit = true; };
    # automation = { claudeCodeIntegration = true; };
    };
  };
}
