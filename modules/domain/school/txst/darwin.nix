{...}: {
  ##########################################################################
  #
  #  Texas State University specific applications.
  #
  #  Microsoft 365 is provided to students via the school's Office 365
  #  license. These apps are installed from the Mac App Store; the user
  #  must sign in with their @txstate.edu account once after install to
  #  activate the license.
  #
  ##########################################################################
  homebrew.masApps = {
    "Microsoft Excel" = 462058435;
    "Microsoft Outlook" = 985367838;
    "Microsoft PowerPoint" = 462062816;
    "Microsoft Word" = 462054704;
    "OneDrive" = 823766827;
    # Add when needed:
    # "Microsoft OneNote" = 784801555;
  };

  # Microsoft Teams is NOT on the Mac App Store (only third-party "join a
  # Teams meeting" clones are), so it has to come from the cask. The cask
  # installs MicrosoftTeams.pkg and the app self-updates afterwards.
  # Requires macOS >= 14.
  homebrew.casks = [
    "microsoft-teams" # Classes / group work — sign in with @txstate.edu
  ];

  # iOS/iPad apps that run on Apple Silicon Macs cannot be installed via mas.
  # The mas CLI is bound to the macOS-only StoreFoundation framework and
  # cannot acquire iOS-bundle apps even when they appear in the Mac App Store's
  # "iPhone & iPad Apps" tab. See: https://github.com/mas-cli/mas/issues/659
  #
  # Install these manually from App Store.app -> "iPhone & iPad Apps" tab:
  #   - Canvas by Instructure (id 480883488) — Texas State courses
}
