{
  config,
  pkgs,
  ...
}: let
  logDir = "${config.home.homeDirectory}/Library/Logs";

  # No KeepAlive: quitting from the menu bar must stick until the next login.
  loginAgent = name: program: {
    enable = true;
    config = {
      Program = program;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "${logDir}/${name}.log";
      StandardErrorPath = "${logDir}/${name}.err.log";
    };
  };
in {
  home.packages = [pkgs.stats pkgs.keepingyouawake];

  launchd.agents.stats = loginAgent "stats" "${pkgs.stats}/Applications/Stats.app/Contents/MacOS/Stats";
  launchd.agents.keepingyouawake =
    loginAgent "keepingyouawake" "${pkgs.keepingyouawake}/Applications/KeepingYouAwake.app/Contents/MacOS/KeepingYouAwake";

  targets.darwin.defaults."eu.exelban.Stats" = {
    # The Nix store is read-only, so the app's self-updater can only fail or drift from the pin.
    "update-interval" = "Never";
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
    SUEnableAutomaticChecks = false;
    SUAutomaticallyUpdate = false;
  };
}
