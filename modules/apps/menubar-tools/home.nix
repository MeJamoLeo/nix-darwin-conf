{...}: let
  # A full path, not `open -a`: LaunchServices can still resolve the name to an old Nix-store copy.
  # No KeepAlive: quitting from the menu bar must stick until the next login.
  loginAgent = app: {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/open" "-g" "/Applications/${app}.app"];
      RunAtLoad = true;
    };
  };
in {
  launchd.agents.stats = loginAgent "Stats";
  launchd.agents.keepingyouawake = loginAgent "KeepingYouAwake";
  launchd.agents.hidden-bar = loginAgent "Hidden Bar";

  targets.darwin.defaults."eu.exelban.Stats" = {
    # homebrew.onActivation.upgrade is off, so the app has to update itself.
    "update-interval" = "Silent";
    # Login start belongs to launchd; the first-run wizard would register a second login item.
    setupProcess = true;

    CPU_state = true;
    GPU_state = true;
    RAM_state = true;
    Disk_state = true;
    Network_state = false;
    Battery_state = false;
    Bluetooth_state = false;
    Sensors_state = false;
    Clock_state = false;

    CPU_widget = "line_chart";
    CPU_line_chart_box = false;
    CPU_line_chart_label = true;

    GPU_widget = "line_chart";
    GPU_line_chart_box = false;
    GPU_line_chart_color = "secondGreen";
    GPU_line_chart_frame = false;
    GPU_line_chart_label = true;
    GPU_line_chart_value = false;

    RAM_widget = "line_chart";
    RAM_line_chart_box = false;
    RAM_line_chart_color = "secondRed";
    RAM_line_chart_gradientFill = true;
    RAM_line_chart_label = true;

    Disk_widget = "pie_chart";
    Disk_pie_chart_label = true;
  };

  targets.darwin.defaults."info.marcel-dierkes.KeepingYouAwake" = {
    SUEnableAutomaticChecks = true;
    SUAutomaticallyUpdate = true;
  };
}
