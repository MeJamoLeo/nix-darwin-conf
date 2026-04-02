{...}: {
  services.neru = {
    enable = true;
    config = ''
      [general]
      excluded_apps = []
      accessibility_check_on_start = true
      kb_layout_to_use = ""
      passthrough_unbounded_keys = false
      should_exit_after_passthrough = false
      passthrough_unbounded_keys_blacklist = []
      hide_overlay_in_screen_share = false

      [hotkeys]
      "Cmd+Shift+Space" = "hints"
      "Cmd+Shift+G" = "grid"
      "Cmd+Shift+C" = "recursive_grid"
      "Cmd+Shift+S" = "scroll"

      [hints]
      enabled = true
      hint_characters = "asdfghjkl"
      max_depth = 50
      parallel_threshold = 20
      include_menubar_hints = false
      additional_menubar_hints_targets = [
          "com.apple.TextInputMenuAgent",
          "com.apple.controlcenter",
          "com.apple.systemuiserver",
      ]
      include_dock_hints = false
      include_nc_hints = false
      include_stage_manager_hints = false
      detect_mission_control = false
      clickable_roles = [
          "AXButton",
          "AXComboBox",
          "AXCheckBox",
          "AXRadioButton",
          "AXLink",
          "AXPopUpButton",
          "AXTextField",
          "AXSlider",
          "AXTabButton",
          "AXSwitch",
          "AXDisclosureTriangle",
          "AXTextArea",
          "AXMenuButton",
          "AXMenuItem",
          "AXCell",
          "AXRow",
      ]
      ignore_clickable_check = false

      [hints.hotkeys]
      "Escape" = "idle"
      "Ctrl+[" = "idle"
      "Backspace" = "action backspace"
      "Shift+J" = "action left_click"
      "Shift+K" = "action right_click"
      "Shift+M" = "action middle_click"
      "Shift+I" = "action mouse_down"
      "Shift+U" = "action mouse_up"
      "Up" = "action move_mouse_relative --dx=0 --dy=-10"
      "Down" = "action move_mouse_relative --dx=0 --dy=10"
      "Left" = "action move_mouse_relative --dx=-10 --dy=0"
      "Right" = "action move_mouse_relative --dx=10 --dy=0"

      [hints.additional_ax_support]
      enable = false
      additional_electron_bundles = []
      additional_chromium_bundles = []
      additional_firefox_bundles = []

      [hints.ui]
      font_size = 10
      font_family = ""
      border_radius = -1
      padding_x = -1
      padding_y = -1
      border_width = 1
      background_color_light = "#F200CFCF"
      background_color_dark = "#F2007A9E"
      text_color_light = "#FF003554"
      text_color_dark = "#FFFFFFFF"
      matched_text_color_light = "#FFAAEEFF"
      matched_text_color_dark = "#FF003554"
      border_color_light = "#FF008A8A"
      border_color_dark = "#FF00B4D8"

      [grid]
      enabled = true
      characters = "abcdefghijklmnpqrstuvwxyz"
      sublayer_keys = "uiojklm,."
      live_match_update = true
      hide_unmatched = true
      prewarm_enabled = true
      enable_gc = false

      [grid.hotkeys]
      "Escape" = "idle"
      "Ctrl+[" = "idle"
      "Space" = "action reset"
      "Backspace" = "action backspace"
      "Shift+J" = "action left_click"
      "Shift+K" = "action right_click"
      "Shift+M" = "action middle_click"
      "Shift+I" = "action mouse_down"
      "Shift+U" = "action mouse_up"
      "Up" = "action move_mouse_relative --dx=0 --dy=-10"
      "Down" = "action move_mouse_relative --dx=0 --dy=10"
      "Left" = "action move_mouse_relative --dx=-10 --dy=0"
      "Right" = "action move_mouse_relative --dx=10 --dy=0"

      [grid.ui]
      font_size = 10
      font_family = ""
      border_width = 1
      background_color_light = "#9900B4D8"
      background_color_dark = "#99003554"
      text_color_light = "#FF003554"
      text_color_dark = "#FFB3E8F5"
      matched_text_color_light = "#FFAAEEFF"
      matched_text_color_dark = "#FFFFFFFF"
      matched_background_color_light = "#B300CFCF"
      matched_background_color_dark = "#B300B4D8"
      matched_border_color_light = "#B300CFCF"
      matched_border_color_dark = "#B300B4D8"
      border_color_light = "#9900B4D8"
      border_color_dark = "#99003554"

      [recursive_grid]
      enabled = true
      grid_cols = 2
      grid_rows = 2
      keys = "uijk"
      min_size_width = 25
      min_size_height = 25
      max_depth = 10

      [recursive_grid.hotkeys]
      "Escape" = "idle"
      "Ctrl+[" = "idle"
      "Space" = "action reset"
      "Backspace" = "action backspace"
      "Shift+J" = "action left_click"
      "Shift+K" = "action right_click"
      "Shift+M" = "action middle_click"
      "Shift+I" = "action mouse_down"
      "Shift+U" = "action mouse_up"
      "Up" = "action move_mouse_relative --dx=0 --dy=-10"
      "Down" = "action move_mouse_relative --dx=0 --dy=10"
      "Left" = "action move_mouse_relative --dx=-10 --dy=0"
      "Right" = "action move_mouse_relative --dx=10 --dy=0"

      [recursive_grid.ui]
      line_color_light = "#FF007A9E"
      line_color_dark = "#FF00CFCF"
      line_width = 1
      highlight_color_light = "#4D007A9E"
      highlight_color_dark = "#4D00CFCF"
      text_color_light = "#FF007A9E"
      text_color_dark = "#FF00CFCF"
      font_size = 10
      font_family = ""
      label_background = false
      label_background_color_light = "#FFAAEEFF"
      label_background_color_dark = "#FF003554"
      label_background_padding_x = -1
      label_background_padding_y = -1
      label_background_border_radius = -1
      label_background_border_width = 1
      sub_key_preview = false
      sub_key_preview_font_size = 8
      sub_key_preview_autohide_multiplier = 1.5
      sub_key_preview_text_color_light = "#66007A9E"
      sub_key_preview_text_color_dark = "#6600CFCF"

      [scroll]
      scroll_step = 50
      scroll_step_half = 500
      scroll_step_full = 1000000

      [scroll.hotkeys]
      "Escape" = "idle"
      "Ctrl+[" = "idle"
      "k" = "action scroll_up"
      "j" = "action scroll_down"
      "h" = "action scroll_left"
      "l" = "action scroll_right"
      "gg" = "action go_top"
      "Shift+G" = "action go_bottom"
      "u" = "action page_up"
      "d" = "action page_down"
      "Shift+J" = "action left_click"
      "Shift+K" = "action right_click"
      "Shift+M" = "action middle_click"
      "Shift+I" = "action mouse_down"
      "Shift+U" = "action mouse_up"
      "Up" = "action move_mouse_relative --dx=0 --dy=-10"
      "Down" = "action move_mouse_relative --dx=0 --dy=10"
      "Left" = "action move_mouse_relative --dx=-10 --dy=0"
      "Right" = "action move_mouse_relative --dx=10 --dy=0"

      [mode_indicator]

      [mode_indicator.scroll]
      enabled = true
      text = "Scroll"

      [mode_indicator.hints]
      enabled = false
      text = "Hints"

      [mode_indicator.grid]
      enabled = false
      text = "Grid"

      [mode_indicator.recursive_grid]
      enabled = false
      text = "Recursive Grid"

      [mode_indicator.ui]
      font_size = 10
      font_family = ""
      background_color_light = "#F200CFCF"
      background_color_dark = "#F200CFCF"
      text_color_light = "#FF003554"
      text_color_dark = "#FF003554"
      border_color_light = "#FF007A9E"
      border_color_dark = "#FF007A9E"
      border_width = 1
      padding_x = -1
      padding_y = -1
      border_radius = -1
      indicator_x_offset = 20
      indicator_y_offset = 20

      [sticky_modifiers]
      enabled = true
      tap_max_duration = 300
      tap_cooldown = 0

      [sticky_modifiers.ui]
      font_size = 10
      font_family = ""
      background_color_light = "#F200CFCF"
      background_color_dark = "#F200CFCF"
      text_color_light = "#FF003554"
      text_color_dark = "#FF003554"
      border_color_light = "#FF007A9E"
      border_color_dark = "#FF007A9E"
      border_width = 1
      padding_x = -1
      padding_y = -1
      border_radius = -1
      indicator_x_offset = -40
      indicator_y_offset = 20

      [smooth_cursor]
      move_mouse_enabled = false
      steps = 10
      max_duration = 200
      duration_per_pixel = 0.1

      [systray]
      enabled = true

      [logging]
      log_level = "info"
      log_file = ""
      structured_logging = true
      disable_file_logging = true
      max_file_size = 10
      max_backups = 5
      max_age = 30
    '';
  };
}
