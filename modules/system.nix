{
  pkgs,
  username,
  ...
}:
###################################################################################
#
#  macOS's System configuration
#
#  All the configuration options are documented here:
#    https://daiderd.com/nix-darwin/manual/index.html#sec-options
#  Incomplete list of macOS `defaults` commands :
#    https://github.com/yannbertrand/macos-defaults
#
###################################################################################
{
  system = {
    primaryUser = username;
    stateVersion = 5;
    activationScripts.fixSSL.text = ''
      if [ -L /etc/ssl/certs/ca-certificates.crt ] && [ "$(readlink /etc/ssl/certs/ca-certificates.crt)" = "/etc/ssl/cert.pem" ]; then
        echo "SSL certificate symlink already set correctly."
      else
        rm -f /etc/ssl/certs/ca-certificates.crt
        ln -sf /etc/ssl/cert.pem /etc/ssl/certs/ca-certificates.crt
        echo "Fixed SSL certificate symlink."
      fi
    '';

    defaults = {
      menuExtraClock.Show24Hour = true; # show 24 hour clock

      # customize dock
      dock = {
        autohide = true;
        show-recents = false; # disable recent apps

        # customize Hot Corners(触发角, 鼠标移动到屏幕角落时触发的动作)
        # wvous-tl-corner = 2;  # top-left - Mission Control
        wvous-tr-corner = 2; # top-right - Mission Control
        # wvous-bl-corner = 3;  # bottom-left - Application Windows
        wvous-br-corner = 4; # bottom-right - Desktop
      };

      # customize finder
      finder = {
        _FXShowPosixPathInTitle = true; # show full path in finder title
        AppleShowAllExtensions = true; # show all file extensions
        FXEnableExtensionChangeWarning = false; # disable warning when changing file extension
        QuitMenuItem = true; # enable quit menu item
        ShowPathbar = true; # show path bar
        ShowStatusBar = true; # show status bar
      };

      # customize trackpad
      trackpad = {
        Clicking = true; # enable tap to click
        TrackpadRightClick = true; # enable two finger right click
        TrackpadThreeFingerDrag = true; # enable three finger drag
      };

      # customize settings that not supported by nix-darwin directly
      # Incomplete list of macOS `defaults` commands :
      #   https://github.com/yannbertrand/macos-defaults
      NSGlobalDomain = {
        # `defaults read NSGlobalDomain "xxx"`
        "com.apple.swipescrolldirection" = true; # enable natural scrolling(default to true)
        "com.apple.sound.beep.feedback" = 0; # disable beep sound when pressing volume up/down key
        AppleInterfaceStyle = "Dark"; # dark mode
        AppleKeyboardUIMode = 3; # Mode 3 enables full keyboard control.
        ApplePressAndHoldEnabled = false; # enable press and hold

        # If you press and hold certain keyboard keys when in a text area, the key's character begins to repeat.
        # This is very useful for vim users, they use `hjkl` to move cursor.
        # sets how long it takes before it starts repeating.
        InitialKeyRepeat = 15; # normal minimum is 15 (225 ms), maximum is 120 (1800 ms)
        # sets how fast it repeats once it starts.
        KeyRepeat = 2; # normal minimum is 2 (30 ms), maximum is 120 (1800 ms)

        NSAutomaticCapitalizationEnabled = false; # disable auto capitalization
        NSAutomaticDashSubstitutionEnabled = false; # disable auto dash substitution
        NSAutomaticPeriodSubstitutionEnabled = false; # disable auto period substitution
        NSAutomaticQuoteSubstitutionEnabled = false; # disable auto quote substitution
        NSAutomaticSpellingCorrectionEnabled = true; # enable auto spelling correction
        NSNavPanelExpandedStateForSaveMode = true; # expand save panel by default
        NSNavPanelExpandedStateForSaveMode2 = true;
      };

      # Customize settings that not supported by nix-darwin directly
      # see the source code of this project to get more undocumented options:
      #    https://github.com/rgcr/m-cli
      #
      # All custom entries can be found by running `defaults read` command.
      # or `defaults read xxx` to read a specific domain.
      CustomUserPreferences = {
        ".GlobalPreferences" = {
          AppleSpacesSwitchOnActivate = true;
          "com.apple.mouse.scaling" = 15.0; # マウススケーリング（速度）の設定
        };
        "com.apple.symbolichotkeys" = {
          AppleSymbolicHotKeys = {
            # Mission Control: Switch to Desktop 1-9 (Ctrl+1..9)
            "118" = {
              enabled = 1;
              value = {
                parameters = [65535 18 262144];
                type = "standard";
              };
            };
            "119" = {
              enabled = 1;
              value = {
                parameters = [65535 19 262144];
                type = "standard";
              };
            };
            "120" = {
              enabled = 1;
              value = {
                parameters = [65535 20 262144];
                type = "standard";
              };
            };
            "121" = {
              enabled = 1;
              value = {
                parameters = [65535 21 262144];
                type = "standard";
              };
            };
            "122" = {
              enabled = 1;
              value = {
                parameters = [65535 23 262144];
                type = "standard";
              };
            };
            "123" = {
              enabled = 1;
              value = {
                parameters = [65535 22 262144];
                type = "standard";
              };
            };
            "124" = {
              enabled = 1;
              value = {
                parameters = [65535 26 262144];
                type = "standard";
              };
            };
            "125" = {
              enabled = 1;
              value = {
                parameters = [65535 28 262144];
                type = "standard";
              };
            };
            "126" = {
              enabled = 1;
              value = {
                parameters = [65535 25 262144];
                type = "standard";
              };
            };
          };
        };
        NSGlobalDomain = {
          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
        };
        ".com.apple" = {
          universalaccess = {
            reduceMotion = true; # 動きを減らす設定を有効化
          };

          finder = {
            ShowExternalHardDrivesOnDesktop = true;
            ShowHardDrivesOnDesktop = true;
            ShowMountedServersOnDesktop = true;
            ShowRemovableMediaOnDesktop = true;
            _FXSortFoldersFirst = true;
            # When performing a search, search the current folder by default
            FXDefaultSearchScope = "SCcf";
          };

          desktopservices = {
            # Avoid creating .DS_Store files on network or USB volumes
            DSDontWriteNetworkStores = true;
            DSDontWriteUSBStores = true;
          };

          spaces = {
            "spans-displays" = 0; # Display have seperate spaces
          };

          WindowManager = {
            EnableStandardClickToShowDesktop = 0; # Click wallpaper to reveal desktop
            StandardHideDesktopIcons = 0; # Show items on desktop
            HideDesktop = 0; # Do not hide items on desktop & stage manager
            StageManagerHideWidgets = 0;
            StandardHideWidgets = 1;
          };

          screensaver = {
            # Require password immediately after sleep or screen saver begins
            askForPassword = 1;
            askForPasswordDelay = 0;
          };

          screencapture = {
            location = "~/Desktop";
            type = "png";
          };

          AdLib = {
            allowApplePersonalizedAdvertising = false;
          };

          ImageCapture = {
            disableHotPlug = true; # Prevent Photos from opening automatically when devices are plugged in
          };
        };
      };

      loginwindow = {
        GuestEnabled = false; # disable guest user
        SHOWFULLNAME = true; # show full name in login window
      };
    };

    # keyboard settings is not very useful on macOS
    # the most important thing is to remap option key to alt key globally,
    # but it's not supported by macOS yet.
    keyboard = {
      enableKeyMapping = true; # enable key mapping so that we can use `option` as `control`

      # NOTE: do NOT support remap capslock to both control and escape at the same time
      remapCapsLockToControl = true; # remap caps lock to control, useful for emac users
      remapCapsLockToEscape = false; # remap caps lock to escape, useful for vim users

      # swap left command and left alt
      # so it matches common keyboard layout: `ctrl | command | alt`
      #
      # disabled, caused only problems!
      swapLeftCommandAndLeftAlt = false;
    };
  };

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  # this is required if you want to use darwin's default shell - zsh
  programs.zsh.enable = true;
  environment.shells = [
    pkgs.zsh
  ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Fonts
  fonts = {
    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      # selected nerd fonts (temporarily disabled due to build warnings)
      # pkgs.nerdfontsSymbolsOnly
      # (pkgs.nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" "Iosevka" ]; })
    ];
  };
}
