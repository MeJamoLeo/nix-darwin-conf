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
      if [ -f "$SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq --argjson nix "$NIX_SETTINGS" '. * $nix' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        echo "$NIX_SETTINGS" | ${pkgs.jq}/bin/jq . > "$SETTINGS_FILE"
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
