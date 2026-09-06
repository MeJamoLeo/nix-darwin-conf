# ⚠ このファイルは modules/apps/omniwm/home.nix の `settings` の実体。
#
#   ★ 2026-09-05 に**全面リセット**した。それ以前の版（AeroSpace 由来の 3×3 グリッド・
#     9ワークスペース宣言・appRules 13件・独自キー配置）は git 履歴にある
#     （最後は 87c9e70 の親）。混ざったコンテキストを一度捨てて、
#     **OmniWM の素の既定 + 明示的な差分だけ**という形に組み直したもの。
#
#   ★ 既定値は推測ではなく**実測で採取**した：live の settings.toml を退避 →
#     OmniWM を再起動 → 生成された素の settings.toml を採取、という手順。
#     そのとき判明したこと：
#       - appRules 13件（Chrome / Safari / Zed / Discord 等の最小サイズ）は
#         **OmniWM の組み込み既定**。以前の宣言は既定の書き写しだった。
#       - workspaces の既定は **9件**。公式 settings-reference が
#         「`1`–`5` と `8`–`9` が main、`6`（❤️）と `7`（🚀）が secondary」と明記し、
#         `omniwmctl query workspaces` の実測も 1,2,3,4,5,8,9,6,7 の順で一致する。
#         ⚠ ただし **settings.toml には 7件しか永続化されない**（8 と 9 が書かれない）。
#         ファイルとランタイムが食い違う。採取直後にファイルだけ見て「既定は7件」と
#         誤読したが、8/9 は動的生成ではなく既定の一部である。
#       - borders の既定は enabled = true / width = 5.0 / シアン。以前 JankyBorders に
#         逃がしていた分はここへ戻した（home.nix の該当節を参照）。
#       - `general.ipcEnabled` の既定は **false**。omniwmctl が全滅するので下で上書きする。
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
#   record にしか再帰せず、配列はテンプレート側が丸ごと勝つ。だから `hotkeys` は
#   169件を全件書いている（減らすと残りが Unassigned に飛ぶ）。逆に `workspaces` と
#   `appRules` は**一切書かない**＝ live 側（＝ OmniWM の既定）がそのまま残る。
#
# ──────────────────────────────────────────────────────────────────────────
#  素の既定からの差分は、下記の 8 つだけ。増やすときはここに追記すること。
#
#   1. general.ipcEnabled = true
#        既定 false。false だと ~/Library/Caches/com.barut.OmniWM/ipc.sock が
#        開かず omniwmctl（query / watch / rule）が全滅する。
#
#   2. 方向キーを矢印から H/J/K/L へ
#        focus.{left,down,up,right}            Option+矢印        → Option+H/J/K/L
#        move.{left,down,up,right}             Option+Shift+矢印  → Option+Shift+H/J/K/L
#        moveColumn.{left,right}               Ctrl+Opt+Shift+矢印 → Ctrl+Opt+Shift+H/L
#        moveWindowToWorkspace{Up,Down}        Ctrl+Opt+Shift+↑↓  → Ctrl+Opt+Shift+K/J
#        ※ 上記が既定で矢印を使っていた全12件。矢印キーは一切使わなくなる。
#
#   3. toggleWorkspaceLayout = Unassigned
#        既定は Option+Shift+L だが、上の move.right と衝突するため外した。
#        （リセット前の設定でも Unassigned だったので実害なし。
#          CLI の `omniwmctl command toggle-workspace-layout` は使える。）
#
#   4. ワークスペースの相対切替を Option+U / Option+I に割り当て
#        switchWorkspace.next      未割当 → Option+U   （niri の Mod+U = down 相当）
#        switchWorkspace.previous  未割当 → Option+I   （niri の Mod+I = up   相当）
#        ⚠ 向きは niri の既定に合わせてある。**リセット前の設定とは逆**
#          （旧: Option+I = next / Option+U = previous）。逆が良ければ2行を入れ替える。
#        ⚠ 末尾を越えたときに createDynamicWorkspace を踏んでワークスペースが
#          増えるかは**未確認**。増殖の実測は相対「移動」で踏んだ話で、
#          フォーカス切替では確かめていない。連打して
#          `omniwmctl query workspaces` が7件を超えないか見ること。
#
#   5. モニタ切替を Command 系から Option 系へ移し、Tab 一族を整理
#        focusMonitorNext      Control+Command+Tab   → Control+Option+Tab
#        focusMonitorPrevious  未割当                → Control+Option+Shift+Tab
#        focusMonitorLast      Control+Command+Grave → Control+Option+Grave
#        workspaceBackAndForth Control+Option+Tab    → Option+Shift+Tab（玉突きで退避）
#      これで修飾キーから Command が消え、Tab の粒度が段になる：
#        Option+Tab              直前の**窓**            (focusPrevious)
#        Option+Shift+Tab        直前の**ワークスペース** (workspaceBackAndForth)
#        Control+Option+Tab      次の**モニタ**          (focusMonitorNext)
#        Control+Option+Shift+Tab 前の**モニタ**         (focusMonitorPrevious)
#
#   6. カラムへの窓の出し入れを niri の定位置へ（Option+Comma / Option+Period）
#        niri 既定は `Mod+Comma = consume-window-into-column` /
#        `Mod+Period = expel-window-from-column` / `Mod+R = switch-preset-column-width`
#        で、OmniWM 既定は同じ2キーを cycleSize に使っている。niri 側に寄せた：
#          consumeWindowIntoColumn  未割当        → Option+Comma
#          expelWindowFromColumn    未割当        → Option+Period
#          cycleSizeForward         Option+Period → Option+R          （niri の Mod+R）
#          cycleSizeBackward        Option+Comma  → Control+Option+R  （玉突き）
#          resetWindowSecondarySpan Control+Option+R → Unassigned     （玉突きの玉突き）
#        resetWindowSecondarySpan は使用頻度が低いので捨てた。必要なら
#        `omniwmctl command reset-window-secondary-span` で叩ける。
#        ⚠ niri の `Mod+BracketLeft/Right`（consume-or-expel の左右版）は
#          **OmniWM に hotkey ID が無い**（169 ID を全走査して0件）。CLI には
#          `consume-or-expel-window-left/right` があるので、要るなら skhd 等へ逃がす。
#
#   7. Option+一文字を3つ埋めた
#        toggleOverview               Option+Shift+O → Option+O （niri の Mod+O）
#        toggleFocusedWindowFloating  未割当         → Option+V （niri の Mod+V）
#        centerColumn                 未割当         → Option+C
#      Overview は一瞬開いて閉じる用途なので一文字に降ろした。centerColumn は niri に
#      対応する既定バインドが無く、theskumar/dotfiles が Option+C を当てている実例に倣った。
#      ⚠ Overview は**画面収録の権限**が要る（アクセシビリティ・入力監視は必須、
#        画面収録は Overview 用に任意）。tanegashima では許可済みだが、ogasawara の
#        初回起動時に訊かれる可能性がある。
#
#   8. ワークスペースの上下移動を U/I に集約し、修飾キーで対象の粒度を表す
#        moveWindowToWorkspaceDown  Ctrl+Opt+Shift+J        → Option+Shift+U
#        moveWindowToWorkspaceUp    Ctrl+Opt+Shift+K        → Option+Shift+I
#        moveColumnToWorkspaceDown  Ctrl+Opt+Shift+Page Down → Control+Option+Shift+U
#        moveColumnToWorkspaceUp    Ctrl+Opt+Shift+Page Up   → Control+Option+Shift+I
#      差分4の Option+U / Option+I（フォーカス移動）の派生として3段になる：
#        Option+U / Option+I               フォーカスが下 / 上のワークスペースへ
#        Option+Shift+U / I                **窓1枚**を下 / 上へ送る
#        Control+Option+Shift+U / I        **カラムごと**下 / 上へ送る
#      修飾が増えるほど動かす対象が大きくなる。`Option+Shift+H/J/K/L`（窓の移動）と
#      同じく「Shift が付いたら動かす」で揃う。向きは U=Down / I=Up で統一。
#      これで Ctrl+Opt+Shift+J / K / Page Up / Page Down の4つが空く。
#      ⚠ 相対移動は「現在のモニタの巡回」内で閉じる（フォーカス切替では ws5 → ws1 に
#        折り返すのを実測済み）。移動系が末尾でどう振る舞うかは**未確認**。
#      ※ 窓を**番号指定**で送るのは既存の Option+Shift+1..9（moveToWorkspace.*）。
#        こちらは絶対指定で、U/I の相対指定とは用途が分かれる。
# ──────────────────────────────────────────────────────────────────────────
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
    (hk "switchWorkspace.0" "Option+1")
    (hk "moveToWorkspace.0" "Option+Shift+1")
    (hk "switchWorkspace.1" "Option+2")
    (hk "moveToWorkspace.1" "Option+Shift+2")
    (hk "switchWorkspace.2" "Option+3")
    (hk "moveToWorkspace.2" "Option+Shift+3")
    (hk "switchWorkspace.3" "Option+4")
    (hk "moveToWorkspace.3" "Option+Shift+4")
    (hk "switchWorkspace.4" "Option+5")
    (hk "moveToWorkspace.4" "Option+Shift+5")
    (hk "switchWorkspace.5" "Option+6")
    (hk "moveToWorkspace.5" "Option+Shift+6")
    (hk "switchWorkspace.6" "Option+7")
    (hk "moveToWorkspace.6" "Option+Shift+7")
    (hk "switchWorkspace.7" "Option+8")
    (hk "moveToWorkspace.7" "Option+Shift+8")
    (hk "switchWorkspace.8" "Option+9")
    (hk "moveToWorkspace.8" "Option+Shift+9")
    (hk "workspaceBackAndForth" "Option+Shift+Tab")
    (hk "switchWorkspace.next" "Option+U")
    (hk "switchWorkspace.previous" "Option+I")
    (hk "focus.left" "Option+H")
    (hk "focus.down" "Option+J")
    (hk "focus.up" "Option+K")
    (hk "focus.right" "Option+L")
    (hk "focusPrevious" "Option+Tab")
    (hk "focusDownOrLeft" "Unassigned")
    (hk "focusUpOrRight" "Unassigned")
    (hk "focusWindowTop" "Unassigned")
    (hk "focusWindowBottom" "Unassigned")
    (hk "focusWindowDownOrTop" "Unassigned")
    (hk "focusWindowUpOrBottom" "Unassigned")
    (hk "focusWindowOrWorkspaceDown" "Unassigned")
    (hk "focusWindowOrWorkspaceUp" "Unassigned")
    (hk "centerColumn" "Option+C")
    (hk "centerVisibleColumns" "Unassigned")
    (hk "moveWindowToWorkspaceUp" "Option+Shift+I")
    (hk "moveWindowToWorkspaceDown" "Option+Shift+U")
    (hk "moveColumnToWorkspaceUp" "Control+Option+Shift+I")
    (hk "moveColumnToWorkspaceDown" "Control+Option+Shift+U")
    (hk "moveColumnToWorkspace.0" "Unassigned")
    (hk "moveColumnToWorkspace.1" "Unassigned")
    (hk "moveColumnToWorkspace.2" "Unassigned")
    (hk "moveColumnToWorkspace.3" "Unassigned")
    (hk "moveColumnToWorkspace.4" "Unassigned")
    (hk "moveColumnToWorkspace.5" "Unassigned")
    (hk "moveColumnToWorkspace.6" "Unassigned")
    (hk "moveColumnToWorkspace.7" "Unassigned")
    (hk "moveColumnToWorkspace.8" "Unassigned")
    (hk "move.left" "Option+Shift+H")
    (hk "move.down" "Option+Shift+J")
    (hk "move.up" "Option+Shift+K")
    (hk "move.right" "Option+Shift+L")
    (hk "moveWindowDown" "Unassigned")
    (hk "moveWindowUp" "Unassigned")
    (hk "moveWindowDownOrToWorkspaceDown" "Unassigned")
    (hk "moveWindowUpOrToWorkspaceUp" "Unassigned")
    (hk "consumeWindowIntoColumn" "Option+Comma")
    (hk "expelWindowFromColumn" "Option+Period")
    (hk "focusMonitorNext" "Control+Option+Tab")
    (hk "focusMonitorPrevious" "Control+Option+Shift+Tab")
    (hk "focusMonitorLast" "Control+Option+Grave")
    (hk "moveWorkspaceToMonitor.left" "Unassigned")
    (hk "moveWorkspaceToMonitor.right" "Unassigned")
    (hk "moveWorkspaceToMonitor.up" "Unassigned")
    (hk "moveWorkspaceToMonitor.down" "Unassigned")
    (hk "moveWindowToMonitor.left" "Unassigned")
    (hk "moveWindowToMonitor.right" "Unassigned")
    (hk "moveWindowToMonitor.up" "Unassigned")
    (hk "moveWindowToMonitor.down" "Unassigned")
    (hk "toggleFullscreen" "Option+Return")
    (hk "toggleNativeFullscreen" "Unassigned")
    (hk "moveColumn.left" "Control+Option+Shift+H")
    (hk "moveColumn.right" "Control+Option+Shift+L")
    (hk "moveColumn.up" "Unassigned")
    (hk "moveColumn.down" "Unassigned")
    (hk "moveColumnToFirst" "Control+Option+Home")
    (hk "moveColumnToLast" "Control+Option+End")
    (hk "toggleColumnTabbed" "Option+T")
    (hk "focusColumnFirst" "Option+Home")
    (hk "focusColumnLast" "Option+End")
    (hk "focusColumn.0" "Control+Option+1")
    (hk "focusColumn.1" "Control+Option+2")
    (hk "focusColumn.2" "Control+Option+3")
    (hk "focusColumn.3" "Control+Option+4")
    (hk "focusColumn.4" "Control+Option+5")
    (hk "focusColumn.5" "Control+Option+6")
    (hk "focusColumn.6" "Control+Option+7")
    (hk "focusColumn.7" "Control+Option+8")
    (hk "focusColumn.8" "Control+Option+9")
    (hk "focusWindowInColumn.1" "Unassigned")
    (hk "focusWindowInColumn.2" "Unassigned")
    (hk "focusWindowInColumn.3" "Unassigned")
    (hk "focusWindowInColumn.4" "Unassigned")
    (hk "focusWindowInColumn.5" "Unassigned")
    (hk "focusWindowInColumn.6" "Unassigned")
    (hk "focusWindowInColumn.7" "Unassigned")
    (hk "focusWindowInColumn.8" "Unassigned")
    (hk "focusWindowInColumn.9" "Unassigned")
    (hk "moveColumnToIndex.1" "Unassigned")
    (hk "moveColumnToIndex.2" "Unassigned")
    (hk "moveColumnToIndex.3" "Unassigned")
    (hk "moveColumnToIndex.4" "Unassigned")
    (hk "moveColumnToIndex.5" "Unassigned")
    (hk "moveColumnToIndex.6" "Unassigned")
    (hk "moveColumnToIndex.7" "Unassigned")
    (hk "moveColumnToIndex.8" "Unassigned")
    (hk "moveColumnToIndex.9" "Unassigned")
    (hk "cycleSizeForward" "Option+R")
    (hk "cycleSizeBackward" "Control+Option+R")
    (hk "cycleWindowPrimarySpanForward" "Unassigned")
    (hk "cycleWindowPrimarySpanBackward" "Unassigned")
    (hk "cycleWindowSecondarySpanForward" "Unassigned")
    (hk "cycleWindowSecondarySpanBackward" "Unassigned")
    (hk "toggleContainerFullPrimarySpan" "Option+Shift+F")
    (hk "expandContainerToAvailablePrimarySpan" "Control+Option+F")
    (hk "resetWindowSecondarySpan" "Unassigned")
    (hk "setContainerPrimarySpan.decrease10Percent" "Option+Minus")
    (hk "setContainerPrimarySpan.increase10Percent" "Option+Equal")
    (hk "setWindowPrimarySpan.decrease10Percent" "Unassigned")
    (hk "setWindowPrimarySpan.increase10Percent" "Unassigned")
    (hk "setWindowSecondarySpan.decrease10Percent" "Option+Shift+Minus")
    (hk "setWindowSecondarySpan.increase10Percent" "Option+Shift+Equal")
    (hk "balanceSizes" "Option+Shift+B")
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
    (hk "openCommandPalette" "Control+Option+Space")
    (hk "raiseAllFloatingWindows" "Option+Shift+R")
    (hk "rescueOffscreenWindows" "Unassigned")
    (hk "toggleFocusedWindowFloating" "Option+V")
    (hk "openMenuAnywhere" "Control+Option+M")
    (hk "toggleWorkspaceBarVisibility" "Unassigned")
    (hk "toggleHiddenBarPanel" "Unassigned")
    (hk "toggleQuakeTerminal" "Option+Grave")
    (hk "toggleWorkspaceLayout" "Unassigned")
    (hk "toggleOverview" "Option+O")
    (hk "toggleSystemStats" "Unassigned")
  ];

  # 既定は false。omniwmctl 用のソケットを開かせる（差分 1）。
  general.ipcEnabled = true;
}
