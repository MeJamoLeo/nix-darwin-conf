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
            current_binding = "command_right";
          };
        };
      };
    };
  };
}
