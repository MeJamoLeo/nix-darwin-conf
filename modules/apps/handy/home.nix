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
