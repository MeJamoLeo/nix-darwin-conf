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
  # ★ 2026-10-25: activation から外した（masApps = {}）。理由の全文は
  #   modules/base/homebrew-base/darwin.nix の masApps のコメント。
  #   要点だけ言うと、Spotlight の索引が壊れると brew bundle が全件を再DLし、
  #   この5本（計 10.5 GB）が毎回の activation を止める。
  #   新機体・新学期に入れ直すときは手で1回:
  #     mas install 462058435 985367838 462062816 462054704 823766827
  #   "Microsoft Excel"      = 462058435;
  #   "Microsoft Outlook"    = 985367838;
  #   "Microsoft PowerPoint" = 462062816;
  #   "Microsoft Word"       = 462054704;
  #   "OneDrive"             = 823766827;
  #   # Add when needed:
  #   # "Microsoft OneNote" = 784801555;
  homebrew.masApps = {};

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
