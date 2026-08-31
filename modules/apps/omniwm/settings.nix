# ⚠ このファイルは modules/apps/omniwm/home.nix の `settings` の実体。
#
#   初版は実機の ~/.config/omniwm/settings.toml（994行・2026-08-30）から機械変換したが、
#   以後は**手で維持する**（再生成スクリプトは置かない。GUI で触った差分を取り込むときは
#   live ファイルと diff を取って必要な行だけ写す）。
#
# ★ ここに**書いてはいけない**もの（merge-settings.nu が live 側を残す層）：
#     monitorBarOverrides / monitorDwindleOverrides / monitorGapOverrides /
#     monitorNiriOverrides / monitorOrientationOverrides / monitorRoutingOverrides /
#     [routing] mode
#   これらは `monitorDisplayUUID` がキー＝**物理ディスプレイと机の記述**で、
#   ogasawara と tanegashima で必ず食い違う。実機の GUI（Settings > Monitors）が正。
#
# ★ `schemaVersion` も書かない。OmniWM がスキーマ移行で自分で上げるので、
#   宣言で固定すると移行を潰す。
#
# 🔴 **配列は全件書くか、一切書かないかの二択。** merge-settings.nu の deep-merge は
#   record にしか再帰せず、配列はテンプレート側が丸ごと勝つ。`hotkeys` を9個だけ書くと
#   残り160個が Unassigned に飛ぶ。`workspaces` / `appRules` も同じ。
{
  # hotkeys を1行1バインドに畳むヘルパ。Unassigned も全件残すこと（上の🔴）。

  hotkeys = let
    hk = id: binding: {inherit id binding;};
  in [
    (hk "toggleScratchpad.1" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.1" "Unassigned")
    (hk "toggleScratchpad.2" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.2" "Unassigned")
    (hk "toggleScratchpad.3" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.3" "Unassigned")
    (hk "toggleScratchpad.4" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.4" "Unassigned")
    (hk "toggleScratchpad.5" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.5" "Unassigned")
    (hk "toggleScratchpad.6" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.6" "Unassigned")
    (hk "toggleScratchpad.7" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.7" "Unassigned")
    (hk "toggleScratchpad.8" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.8" "Unassigned")
    (hk "toggleScratchpad.9" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.9" "Unassigned")
    (hk "toggleScratchpad.10" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.10" "Unassigned")
    (hk "switchWorkspace.0" "Option+Q")
    (hk "moveToWorkspace.0" "Control+Option+Shift+Q")
    (hk "switchWorkspace.1" "Option+W")
    (hk "moveToWorkspace.1" "Control+Option+Shift+W")
    (hk "switchWorkspace.2" "Option+E")
    (hk "moveToWorkspace.2" "Control+Option+Shift+E")
    (hk "switchWorkspace.3" "Option+A")
    (hk "moveToWorkspace.3" "Control+Option+Shift+A")
    (hk "switchWorkspace.4" "Option+S")
    (hk "moveToWorkspace.4" "Control+Option+Shift+S")
    (hk "switchWorkspace.5" "Option+D")
    (hk "moveToWorkspace.5" "Control+Option+Shift+D")
    (hk "switchWorkspace.6" "Option+Z")
    (hk "moveToWorkspace.6" "Control+Option+Shift+Z")
    (hk "switchWorkspace.7" "Option+X")
    (hk "moveToWorkspace.7" "Control+Option+Shift+X")
    (hk "switchWorkspace.8" "Option+C")
    (hk "moveToWorkspace.8" "Control+Option+Shift+C")
    (hk "workspaceBackAndForth" "Unassigned")
    (hk "switchWorkspace.next" "Option+I")
    (hk "switchWorkspace.previous" "Option+U")
    (hk "focus.left" "Option+H")
    (hk "focus.down" "Option+J")
    (hk "focus.up" "Option+K")
    (hk "focus.right" "Option+L")
    # ★ Tab 列＝モニタ操作（AeroSpace の alt-tab / alt-shift-tab を引き継ぐ）。
    #   focus 側は Next/Previous で巡回するが、**move 側に非方向の版が無い**ので
    #   縦積み（U32J59x 上 / LG QHD 下）に合わせて up/down を当てている。
    #   横並びに変えたら Control+Option+Shift+H/L（left/right）に読み替えること。
    (hk "focusPrevious" "Unassigned")
    (hk "focusDownOrLeft" "Unassigned")
    (hk "focusUpOrRight" "Unassigned")
    (hk "focusWindowTop" "Unassigned")
    (hk "focusWindowBottom" "Unassigned")
    (hk "focusWindowDownOrTop" "Unassigned")
    (hk "focusWindowUpOrBottom" "Unassigned")
    (hk "focusWindowOrWorkspaceDown" "Unassigned")
    (hk "focusWindowOrWorkspaceUp" "Unassigned")
    (hk "centerColumn" "Option+P")
    (hk "centerVisibleColumns" "Option+Shift+P")
    (hk "moveWindowToWorkspaceUp" "Unassigned")
    (hk "moveWindowToWorkspaceDown" "Unassigned")
    # 🔴 相対移動は末尾を越えると createDynamicWorkspace（requiresConfiguration: false）を
    #   通って**宣言外のワークスペースを生やす**（実測：9→23 まで増殖・GC の発火条件は不明）。
    #   絶対指定（3×3 の文字キー）は configuredWorkspaceNameSet() のガードを通るので増えない。
    #   → 9個固定を保つため相対移動は握らせない。代替は Option+Shift+<文字> の直接指定。
    (hk "moveColumnToWorkspaceUp" "Unassigned")
    (hk "moveColumnToWorkspaceDown" "Unassigned")
    (hk "moveColumnToWorkspace.0" "Option+Shift+Q")
    (hk "moveColumnToWorkspace.1" "Option+Shift+W")
    (hk "moveColumnToWorkspace.2" "Option+Shift+E")
    (hk "moveColumnToWorkspace.3" "Option+Shift+A")
    (hk "moveColumnToWorkspace.4" "Option+Shift+S")
    (hk "moveColumnToWorkspace.5" "Option+Shift+D")
    (hk "moveColumnToWorkspace.6" "Option+Shift+Z")
    (hk "moveColumnToWorkspace.7" "Option+Shift+X")
    (hk "moveColumnToWorkspace.8" "Option+Shift+C")
    (hk "move.left" "Unassigned")
    (hk "move.down" "Option+Shift+J")
    (hk "move.up" "Option+Shift+K")
    (hk "move.right" "Unassigned")
    (hk "moveWindowDown" "Unassigned")
    (hk "moveWindowUp" "Unassigned")
    (hk "moveWindowDownOrToWorkspaceDown" "Unassigned")
    (hk "moveWindowUpOrToWorkspaceUp" "Unassigned")
    (hk "consumeWindowIntoColumn" "Option+Comma")
    (hk "expelWindowFromColumn" "Option+Period")
    (hk "focusMonitorNext" "Option+Tab")
    (hk "focusMonitorPrevious" "Control+Option+Tab")
    (hk "focusMonitorLast" "Option+Grave")
    (hk "moveWorkspaceToMonitor.left" "Control+Option+Shift+U")
    (hk "moveWorkspaceToMonitor.right" "Control+Option+Shift+I")
    (hk "moveWorkspaceToMonitor.up" "Unassigned")
    (hk "moveWorkspaceToMonitor.down" "Unassigned")
    (hk "moveWindowToMonitor.left" "Control+Option+Shift+H")
    (hk "moveWindowToMonitor.right" "Control+Option+Shift+L")
    (hk "moveWindowToMonitor.up" "Option+Shift+Tab")
    (hk "moveWindowToMonitor.down" "Control+Option+Shift+Tab")
    (hk "toggleFullscreen" "Control+Option+F")
    (hk "toggleNativeFullscreen" "Unassigned")
    (hk "moveColumn.left" "Option+Shift+H")
    (hk "moveColumn.right" "Option+Shift+L")
    (hk "moveColumn.up" "Unassigned")
    (hk "moveColumn.down" "Unassigned")
    (hk "moveColumnToFirst" "Option+Shift+Home")
    (hk "moveColumnToLast" "Option+Shift+End")
    # タブ化は外してある（2026-08-30）。タブ化されたカラムは1枚しか表示されず、
    # **どのカラムがタブ化されているかを示す視覚表現が無い**（settings-reference に
    # タブ表示の設定項目も無い）ので、押した本人が見失う。カラム内の複数ウィンドウは
    # 縦積み（全部見える）のままにして、分離は Option+. で行う。
    (hk "toggleColumnTabbed" "Unassigned")
    (hk "focusColumnFirst" "Option+Home")
    (hk "focusColumnLast" "Option+End")
    (hk "focusColumn.0" "Option+1")
    (hk "focusColumn.1" "Option+2")
    (hk "focusColumn.2" "Option+3")
    (hk "focusColumn.3" "Option+4")
    (hk "focusColumn.4" "Option+5")
    (hk "focusColumn.5" "Option+6")
    (hk "focusColumn.6" "Option+7")
    (hk "focusColumn.7" "Option+8")
    (hk "focusColumn.8" "Option+9")
    (hk "focusWindowInColumn.1" "Unassigned")
    (hk "focusWindowInColumn.2" "Unassigned")
    (hk "focusWindowInColumn.3" "Unassigned")
    (hk "focusWindowInColumn.4" "Unassigned")
    (hk "focusWindowInColumn.5" "Unassigned")
    (hk "focusWindowInColumn.6" "Unassigned")
    (hk "focusWindowInColumn.7" "Unassigned")
    (hk "focusWindowInColumn.8" "Unassigned")
    (hk "focusWindowInColumn.9" "Unassigned")
    (hk "moveColumnToIndex.1" "Option+Shift+1")
    (hk "moveColumnToIndex.2" "Option+Shift+2")
    (hk "moveColumnToIndex.3" "Option+Shift+3")
    (hk "moveColumnToIndex.4" "Option+Shift+4")
    (hk "moveColumnToIndex.5" "Option+Shift+5")
    (hk "moveColumnToIndex.6" "Option+Shift+6")
    (hk "moveColumnToIndex.7" "Option+Shift+7")
    (hk "moveColumnToIndex.8" "Option+Shift+8")
    (hk "moveColumnToIndex.9" "Option+Shift+9")
    (hk "cycleSizeForward" "Option+R")
    (hk "cycleSizeBackward" "Control+Option+R")
    (hk "cycleWindowPrimarySpanForward" "Unassigned")
    (hk "cycleWindowPrimarySpanBackward" "Unassigned")
    (hk "cycleWindowSecondarySpanForward" "Control+Option+Shift+R")
    (hk "cycleWindowSecondarySpanBackward" "Unassigned")
    (hk "toggleContainerFullPrimarySpan" "Option+F")
    (hk "expandContainerToAvailablePrimarySpan" "Option+Shift+F")
    (hk "resetWindowSecondarySpan" "Option+Shift+R")
    (hk "setContainerPrimarySpan.decrease10Percent" "Option+Minus")
    (hk "setContainerPrimarySpan.increase10Percent" "Option+Equal")
    (hk "setWindowPrimarySpan.decrease10Percent" "Unassigned")
    (hk "setWindowPrimarySpan.increase10Percent" "Unassigned")
    (hk "setWindowSecondarySpan.decrease10Percent" "Control+Option+Minus")
    (hk "setWindowSecondarySpan.increase10Percent" "Control+Option+Equal")
    (hk "balanceSizes" "Control+Option+B")
    (hk "moveToRoot" "Unassigned")
    (hk "toggleSplit" "Unassigned")
    (hk "swapSplit" "Unassigned")
    (hk "resizeGrow.horizontal" "Unassigned")
    (hk "resizeGrow.vertical" "Unassigned")
    (hk "resizeShrink.horizontal" "Unassigned")
    (hk "resizeShrink.vertical" "Unassigned")
    (hk "resizeFocusedWindow.grow" "Unassigned")
    (hk "resizeFocusedWindow.shrink" "Unassigned")
    (hk "preselect.left" "Unassigned")
    (hk "preselect.right" "Unassigned")
    (hk "preselect.up" "Unassigned")
    (hk "preselect.down" "Unassigned")
    (hk "preselectClear" "Unassigned")
    (hk "openCommandPalette" "Control+Option+P")
    (hk "raiseAllFloatingWindows" "Unassigned")
    (hk "rescueOffscreenWindows" "Unassigned")
    # フローティングは使わない方針（2026-08-30）。全部タイルで通す。
    # ⚠ キーを外してもフローティング窓は消えない——appRules の `--layout float` や
    #   ダイアログ類は依然として浮く。手動で浮かせる口を塞いだだけ。
    (hk "toggleFocusedWindowFloating" "Unassigned")
    (hk "openMenuAnywhere" "Option+Shift+M")
    (hk "toggleWorkspaceBarVisibility" "Unassigned")
    (hk "toggleHiddenBarPanel" "Unassigned")
    (hk "toggleQuakeTerminal" "Option+Return")
    (hk "toggleWorkspaceLayout" "Unassigned")
    (hk "toggleOverview" "Option+O")
    (hk "toggleSystemStats" "Unassigned")
  ];

  appearance = {
    mode = "dark";
  };

  # OmniWM 内蔵のフォーカス枠は切り、AeroSpace 時代から使っている JankyBorders に
  # 描かせる（起動は ./home.nix の launchd agent）。内蔵側の描画に不具合が出たため
  # で、機能自体を捨てたわけではない ── 直ったら enabled = true に戻して
  # home.nix の jankyborders 側を落とせば元に戻る（二重に枠が出るので併用はしない）。
  # width / color は戻したときのために当時の値を残してある。
  borders = {
    enabled = false;
    width = 5.0;
    color = {
      alpha = 1.0;
      blue = 0.979300037944676;
      green = 1.0;
      red = 0.08458520228437894;
    };
  };

  clipboard = {
    historyEnabled = false;
    maxItemBytes = 8388608;
    maxItems = 200;
    maxTotalBytes = 67108864;
  };

  dwindle = {
    defaultSplitRatio = 1.0;
    moveToRootStable = true;
    singleWindowFit = "fill";
    smartSplit = false;
    splitWidthMultiplier = 1.0;
    useGlobalGaps = true;
  };

  focus = {
    crossesMonitorAtEdge = false;
    followsMouse = false;
    followsWindowToMonitor = false;
    lockModifier = "off";
    moveCrossesMonitorAtEdge = false;
    moveMouseToFocusedWindow = false;
    raiseOnMouseFocus = false;
  };

  gaps = {
    fullscreenUsesOuterGaps = false;
    size = 16.0;
    outer = {
      bottom = 0.0;
      left = 0.0;
      right = 0.0;
      top = 0.0;
    };
  };

  general = {
    animationsEnabled = true;
    defaultLayoutType = "niri";
    hotkeysEnabled = true;
    hyperKeyModifiers = "Control+Option+Shift+Command";
    ipcEnabled = true; # omniwmctl 用。false だとソケットが無く query も watch も不可
    preventSleepEnabled = false;
    systemHyperTrigger = "None";
    updateChecksEnabled = true;
  };

  gestures = {
    fingerCount = 3;
    invertDirection = true;
    mouseMoveModifierKey = "option";
    mouseResizeModifierKey = "option";
    scrollEnabled = true;
    scrollModifierKey = "optionShift";
    scrollSensitivity = 5.0;
    trackpadScrollStyle = "snap";
    workspaceSwipeAxis = "vertical";
    workspaceSwipeEnabled = false;
    workspaceSwipeFingerCount = 3;
  };

  hiddenBar = {
    enabled = true;
    hiddenBundleIDs = [];
    rehideIntervalSeconds = 5.0;
  };

  mouseWarp = {
    constrainToArrangement = false;
    enabled = true;
    margin = 1;
  };

  niri = {
    alwaysCenterSingleColumn = false;
    centerFocusedColumn = "never";
    containerPrimarySpanPresets = [
      0.3333333333333333
      0.5
      0.6666666666666666
    ];
    defaultContainerPrimarySpan = 0.5;
    infiniteLoop = false;
    singleWindowFit = "fill";
    visibleContainerCount = 2;
  };

  overview = {
    # 9ワークスペースだと等倍では画面に収まらずスクロールが要る（2026-08-30 実測）。
    # 有効範囲は 50〜150%。Overview を開いて Option+Shift+スクロールで一時的に変えられる
    # ので、良い倍率が分かったらこの値を差し替える（一時ズームは次回開くと基準へ戻る）。
    zoom = 0.7;
    backdrop = {
      alpha = 1.0;
      blue = 0.08;
      green = 0.05;
      red = 0.05;
    };
    windowBorders = {
      hovered = {
        alpha = 1.0;
        blue = 1.0;
        green = 0.6;
        red = 0.4;
      };
      # 既定は RGB 0.3 / alpha 0.5 で、ほぼ黒の backdrop 上では枠が見えない。
      # 選択中でも hover 中でもない窓の境界を出すため明るく・不透明にする。
      normal = {
        alpha = 1.0;
        blue = 0.62;
        green = 0.55;
        red = 0.55;
      };
      selected = {
        alpha = 1.0;
        blue = 0.4;
        green = 0.8;
        red = 0.3;
      };
    };
  };

  quakeTerminal = {
    animationDuration = 0.2;
    autoHide = false;
    backgroundBlurRadius = 0;
    backgroundEffect = "standardBlur";
    enabled = true;
    heightPercent = 50.0;
    monitorMode = "focusedWindow";
    opacity = 1.0;
    position = "center";
    widthPercent = 50.0;
  };

  scratchpads = {
    labels = {};
  };

  statusBar = {
    showAppNames = false;
    showWorkspaceName = false;
    useWorkspaceId = false;
  };

  workspaceBar = {
    backgroundOpacity = 0.1;
    deduplicateAppIcons = false;
    enabled = true;
    excludedBundleIDs = [];
    height = 24.0;
    hideEmptyWorkspaces = false;
    hideInNativeFullscreen = false;
    notchActiveZoneWidth = 180.0;
    notchMode = "moveBelowMenuBar";
    position = "overlappingMenuBar";
    reserveLayoutSpace = false;
    revealHoldMilliseconds = 200.0;
    revealModifier = "off";
    showFloatingWindows = false;
    showLabels = true;
    systemStatsButton = false;
    windowLevel = "popup";
    xOffset = 0.0;
    yOffset = 0.0;
    iconOverrides = {};
  };

  appRules = [
    {
      bundleId = "com.openai.codex";
      id = "6A31F08A-4051-4354-B439-42F4C71894A3";
      minHeight = 600.0;
      minWidth = 800.0;
    }
    {
      bundleId = "com.eltima.cmd1.pro.mas";
      id = "4BA546DA-2875-4BEF-B13F-1539E833B1A0";
      minHeight = 550.0;
      minWidth = 950.0;
    }
    {
      bundleId = "com.google.Chrome";
      id = "486CEFA6-69AA-4A3C-AF27-BCD38F4F138B";
      minHeight = 375.0;
      minWidth = 500.0;
    }
    {
      bundleId = "dev.zed.Zed";
      id = "979F05F4-FFA2-4EDD-B23F-08A9944C759F";
      minHeight = 240.0;
      minWidth = 360.0;
    }
    {
      bundleId = "com.apple.Safari";
      id = "81426D13-C1A5-475E-AFBC-00BBA05042D0";
      minHeight = 220.0;
      minWidth = 574.0;
    }
    {
      bundleId = "app.zen-browser.zen";
      id = "1CF39647-F30D-4E76-9686-79B551F1B094";
      minHeight = 495.0;
      minWidth = 500.0;
    }
    {
      bundleId = "org.mozilla.firefox";
      id = "005C00D3-F665-47F8-BDAE-D80790E9E46B";
      minHeight = 120.0;
      minWidth = 500.0;
    }
    {
      bundleId = "company.thebrowser.dia";
      id = "C21156B1-0224-4998-97E3-8F4FA65B9F3B";
      minHeight = 420.0;
      minWidth = 500.0;
    }
    {
      bundleId = "com.spotify.client";
      id = "2DE9390B-0DB4-4D0C-9ABA-06F76F1D4EA9";
      minHeight = 600.0;
      minWidth = 800.0;
    }
    {
      bundleId = "com.hnc.Discord";
      id = "AF752D95-8497-4844-BE20-4C93E73BAEF2";
      minHeight = 500.0;
      minWidth = 800.0;
    }
    {
      bundleId = "com.mitchellh.ghostty";
      id = "7876C9EF-437E-4D4F-9C27-B1B02F4AABCE";
      minHeight = 48.0;
      minWidth = 90.0;
    }
    {
      bundleId = "com.microsoft.Outlook";
      id = "8ECAB78B-BCDD-4245-BC25-1609A49B1C86";
      minHeight = 650.0;
      minWidth = 930.0;
    }
    {
      bundleId = "com.apple.MobileSMS";
      id = "552FB77D-BF0E-4737-90A6-B5BC6986C579";
      minHeight = 320.0;
      minWidth = 660.0;
    }
  ];

  # ★ 左手 3×3 ＝ ワークスペース。**1行＝1モニタ**（キーの物理的な高さを画面の高さに対応させる。
  #   AeroSpace も上段 q/w/e/r → secondary、下段 z/x/c/v → 3台目、という同じ形だった）。
  #     上段 Q/W/E = 1,2,3 → secondary  ＝ Samsung U32J59x（物理的に上）
  #     中段 A/S/D = 4,5,6 → main       ＝ LG QHD（下・macOS のメインディスプレイ）
  #     下段 Z/X/C = 7,8,9 → **3枚目の予約席**。今は2台なので暫定で main（＝メインのサブ）。
  #   ⚠ 「上のモニタ」と secondary が結びつくのは実機の都合。`omniwmctl query displays` で
  #     LG QHD が MAIN、U32J59x が非 MAIN と実測（2026-08-30）。tanegashima は内蔵1枚なので
  #     secondary 指定のワークスペースは main にフォールバックする**はず（未確認）**——
  #     ドキュメントに記述が無く、2機目で switch するまで確定しない。
  #   ⚠ 同じく2機目で要確認：`workspaces[].id` は ogasawara の実機値をそのままコミットして
  #     いる。tanegashima 側に別 UUID のワークスペースが既に在るとき、配列置換で置き換わる
  #     のか重複するのかを見ていない。当てる前に向こうの settings.toml を覗くこと。
  #
  #   3枚目が来たら type = "specificDisplay" + output に切り替えるが、output は
  #   ディスプレイ識別子＝**UUID 層なのでここには書けない**。`workspaces` は配列なので
  #   テンプレが丸ごと勝つ以上、3枚目を入れる日には下段だけ宣言から外す判断が要る。
  #
  # displayName は置かない＝`name` の数字がそのままバーに出る
  #   （OmniWM 既定は 6=❤️ / 7=🚀 だが除去済み）。
  workspaces = [
    {
      id = "AD36F001-C57E-41A5-AC1D-DF5249D007F0";
      name = "1"; # Option+Q
      layoutType = "niri";
      monitorAssignment = {
        type = "secondary";
      };
    }
    {
      id = "454CECD4-5E9D-4ED1-95D7-979D48817F5F";
      name = "2"; # Option+W
      layoutType = "niri";
      monitorAssignment = {
        type = "secondary";
      };
    }
    {
      id = "BEB842B5-E894-4791-9FD1-397C3CDD3538";
      name = "3"; # Option+E
      layoutType = "niri";
      monitorAssignment = {
        type = "secondary";
      };
    }
    {
      id = "248AA883-2261-4D45-943C-79C0E46A232B";
      name = "4"; # Option+A
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
    {
      id = "8B8C45D6-CE9E-41D9-BD50-BE4989D5E3DE";
      name = "5"; # Option+S
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
    {
      id = "5953F2BF-A378-4266-91B2-287174C4FA4D";
      name = "6"; # Option+D
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
    {
      id = "A7D5E104-6985-4516-8ED5-07F144F2A33D";
      name = "7"; # Option+Z
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
    {
      id = "591FC0A3-78EE-4470-B19D-B852D1C6573A";
      name = "8"; # Option+X
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
    {
      id = "A843A614-A6D1-4D63-8D2F-D4030559154F";
      name = "9"; # Option+C
      layoutType = "niri";
      monitorAssignment = {
        type = "main";
      };
    }
  ];
}
