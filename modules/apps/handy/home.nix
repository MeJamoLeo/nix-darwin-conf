{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.programs.handy;
  settingsFile = "$HOME/Library/Application Support/com.pais.handy/settings_store.json";
  nixSettings = builtins.toJSON {
    settings = cfg.settings;
  };
in {
  options.programs.handy = {
    enable = lib.mkEnableOption "Handy speech-to-text settings management";

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Handy settings to merge into settings_store.json.";
    };
  };

  config = {
    home.activation.handy-settings = lib.mkIf cfg.enable (lib.hm.dag.entryAfter ["writeBoundary"] ''
      SETTINGS_FILE="${settingsFile}"
      NIX_SETTINGS='${nixSettings}'
      # Handy は起動時に settings_store.json を読んでキーバインドを登録するだけで、
      # 稼働中の JSON 変更は拾わない。書き換え前後の sha256 を比較し、実際に内容が
      # 動いたときだけ Handy を再起動する（毎 switch で無条件 kill だと副作用が大きい）。
      before=""
      [ -f "$SETTINGS_FILE" ] && before="$(${pkgs.coreutils}/bin/sha256sum "$SETTINGS_FILE" | cut -c1-64)"
      if [ -f "$SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq --argjson nix "$NIX_SETTINGS" '. * $nix' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        echo "$NIX_SETTINGS" | ${pkgs.jq}/bin/jq . > "$SETTINGS_FILE"
      fi
      after="$(${pkgs.coreutils}/bin/sha256sum "$SETTINGS_FILE" | cut -c1-64)"
      if [ "$before" != "$after" ] && /usr/bin/pgrep -x handy >/dev/null 2>&1; then
        /usr/bin/killall handy 2>/dev/null || true
        # 旧プロセスの解放を待ってから起動（open -a が既存インスタンスに合流するのを避ける）
        for _ in 1 2 3 4 5; do /usr/bin/pgrep -x handy >/dev/null 2>&1 || break; sleep 0.5; done
        /usr/bin/open -a Handy
      fi
    '');

    programs.handy = {
      enable = true;
      settings = {
        push_to_talk = true;
        # ログイン時にメインウィンドウを出さず tray 常駐だけにする（2026-07-30）。
        # Handy 自身の autostart_enabled=true が ~/Library/LaunchAgents/Handy.plist
        # (RunAtLoad, ProgramArguments=Handy.app/Contents/MacOS/handy) を生成するので、
        # start_hidden が false だと毎ログインで設定ウィンドウが前面に出る。
        # GUI 側の値は既に true だったが nix 未宣言のドリフトだったのでここに固定する
        # （autostart_enabled は Handy 自身が書き換えるので宣言しない＝ログイン常駐は GUI 側の意思に従う）。
        start_hidden = true;
        # 値は表示名 "Whisper Turbo" ではなく registry の id。GUI で選んだ結果が入るキーなので
        # 宣言しないと端末ごとにドリフトする。
        # 日英を selected_language="auto" で使い分ける前提で turbo に固定する。
        # cohere-int8 は不採用（2026-08-03 実測）：Handy の accuracy_score は 0.90 で最高だが
        # あれも Open ASR Leaderboard = 英語専用の指標。日本語発話を auto 判定が英語と誤認して
        # 英語の定型句を幻覚する事故が 5件中2件で発生した（"Just say no使い勝手も調べて" 等）。
        # 日本語特化の独立ベンチでも言語明示で CER 0.297 vs turbo 0.184 と負ける。
        # モデル実体は Handy が実行時に落とす。sha256 は upstream registry にあるので fetchurl 化も
        # 可能だが、store と Application Support で二重持ちになるので宣言しない＝実体は GUI 側の管理。
        selected_model = "turbo";
        bindings = {
          transcribe = {
            id = "transcribe";
            name = "Transcribe";
            description = "Converts your speech into text.";
            default_binding = "option+space";
            # 物理 LCtrl が hidutil で F18 化されている (modules/macos-defaults/darwin.nix userKeyMapping)。
            # macOS では F13-F20 のハードウェアイベントに Fn(SecondaryFn) フラグが常に付くため
            # "f18" 単体ではマッチしない（handy-keys v0.3.0 types/key.rs の Fn 注記）。fn+ が必須。
            current_binding = "fn+f18";
          };
          cancel = {
            id = "cancel";
            name = "Cancel";
            description = "Cancels the current recording.";
            # 出所不明の "shift_left+space" が settings に居座っていたので既定値にピン留め
            # （2026-07-16。activation の deep-merge は宣言していないキーを触らないため）。
            default_binding = "escape";
            current_binding = "escape";
          };
        };
      };
    };
  };
}
