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

    # iOS/iPad apps available on Apple Silicon Macs.
    # Canvas LMS — used by Texas State for course materials & submissions.
    "Canvas" = 480883488;
  };
}
