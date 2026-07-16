{...}: {
  # cmux reads ~/.config/cmux/cmux.json. Settings written here become
  # file-managed; anything omitted falls back to in-app Settings.
  # Schema: https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json
  xdg.configFile."cmux/cmux.json" = {
    force = true; # cmuxが起動時に同名ファイルを生成するので上書き許可
    text = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
    schemaVersion = 1;
    # cmux 自身のペインフォーカス移動を nvim 風 hjkl に。
    # cmd+option を使うのは、ターミナル/シェル/内側tmux/nvim と一切
    # 衝突しないため(macOS は cmd 系をターミナルに渡さない)。
    # cmd+option+h だけ macOS の「Hide Others」と被るが、cmux に
    # フォーカスがある間はアプリ側の割当が勝つので実害なし。
    # ペイン分割・ワークスペース等は内側 tmux と cmux デフォルトに任せる。
    # フォーカス移動: cmd+option+hjkl
    # 全部バランス:   equalizeSplits を cmd+option+equals に
    #                "=" 文字はキー名として無効。schema 上は "equals"(or "plus")。
    #                cmux には tmux 風のレイアウト巡回が無いので = が唯一の整列手段。
    # リサイズ:      cmd+ctrl+hjkl は cmux 組込デフォルトで固定(remap不可)
    shortcuts.bindings = {
      focusLeft = "cmd+option+h";
      focusDown = "cmd+option+j";
      focusUp = "cmd+option+k";
      focusRight = "cmd+option+l";
      equalizeSplits = "cmd+option+equals";
    };
    # 設定を増やしたくなったらここに足す。例:
    # app = { sendAnonymousTelemetry = false; warnBeforeQuit = true; };
    # automation = { claudeCodeIntegration = true; };
    };
  };
}
