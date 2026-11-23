{...}: let
  # `open` rather than the binary: casks live in /Applications and their self-updates replace the bundle.
  # No KeepAlive: quitting from the menu bar must stick until the next login.
  loginAgent = app: {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/open" "-g" "-a" app];
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
  };

  targets.darwin.defaults."info.marcel-dierkes.KeepingYouAwake" = {
    SUEnableAutomaticChecks = true;
    SUAutomaticallyUpdate = true;
  };
}
