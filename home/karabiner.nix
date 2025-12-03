{...}: {
  # Karabiner-Elements configuration (requires app installed via Homebrew).
  home.file.".config/karabiner/karabiner.json" = {
    force = true;
    text = builtins.toJSON {
      global = {
        ask_for_confirmation_before_quitting = true;
        show_in_menu_bar = true;
        show_profile_name_in_menu_bar = false;
      };

      profiles = [
        {
          name = "Default";
          selected = true;
          complex_modifications = {
          rules = [
            {
              description = "Map left control to Hyper (cmd+ctrl+alt+shift)";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "left_control";
                    modifiers.optional = ["any"];
                  };
                  to = [
                    {
                      key_code = "left_shift";
                      modifiers = [
                        "left_command"
                        "left_control"
                        "left_option"
                      ];
                    }
                  ];
                }
              ];
            }
            {
              description = "Map left caps lock to left control";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "caps_lock";
                    modifiers.optional = ["any"];
                  };
                  to = [
                    {
                      key_code = "left_control";
                    }
                  ];
                }
              ];
            }
          ];
        };
          devices = [];
          parameters = {};
          simple_modifications = [];
          virtual_hid_keyboard = {
            country_code = 0;
            indicate_sticky_modifier_keys_state = true;
            mouse_key_xy_scale = 100;
          };
        }
      ];
    };
  };
}
